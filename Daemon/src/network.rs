use std::{collections::HashSet, ffi::CStr, fmt, net::Ipv4Addr, path::Path, process::Command};

use serde_json::Value;

const IFCONFIG_CANDIDATES: &[&str] = &[
    "/sbin/ifconfig",
    "/usr/sbin/ifconfig",
    "/bin/ifconfig",
    "/usr/bin/ifconfig",
    "/var/jb/sbin/ifconfig",
    "/var/jb/usr/sbin/ifconfig",
    "/var/jb/bin/ifconfig",
    "/var/jb/usr/bin/ifconfig",
];
const ROUTE_CANDIDATES: &[&str] = &[
    "/sbin/route",
    "/usr/sbin/route",
    "/bin/route",
    "/usr/bin/route",
    "/var/jb/sbin/route",
    "/var/jb/usr/sbin/route",
    "/var/jb/bin/route",
    "/var/jb/usr/bin/route",
];
const MAGIC_DNS_CIDR: Ipv4Cidr = Ipv4Cidr {
    address: Ipv4Addr::new(100, 100, 100, 101),
    prefix: 32,
};

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct Ipv4Cidr {
    pub address: Ipv4Addr,
    pub prefix: u8,
}

impl fmt::Display for Ipv4Cidr {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}/{}", self.address, self.prefix)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NetworkPlan {
    pub address: Ipv4Cidr,
    pub mtu: Option<u64>,
    pub routes: Vec<Ipv4Cidr>,
}

#[derive(Clone, Debug)]
pub struct AppliedNetwork {
    interface: String,
    address: Ipv4Cidr,
    mtu: Option<u64>,
    routes: Vec<Ipv4Cidr>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InterfaceTraffic {
    pub rx_bytes: u64,
    pub tx_bytes: u64,
    pub rx_packets: u64,
    pub tx_packets: u64,
}

impl AppliedNetwork {
    pub fn matches_plan(&self, plan: &NetworkPlan) -> bool {
        self.address == plan.address && self.mtu == plan.mtu && self.routes == plan.routes
    }

    pub fn cleanup(self) {
        for route in self.routes {
            let _ = delete_route(&route);
        }
        let _ = run(
            IFCONFIG_CANDIDATES,
            "ifconfig",
            &[self.interface, "down".to_owned()],
        );
    }
}

pub fn interface_traffic(interface: &str) -> Result<InterfaceTraffic, String> {
    validate_interface(interface)?;
    let mut addrs: *mut libc::ifaddrs = std::ptr::null_mut();
    let result = unsafe { libc::getifaddrs(&mut addrs) };
    if result != 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }

    let mut cursor = addrs;
    let mut traffic = None;
    while !cursor.is_null() {
        let item = unsafe { &*cursor };
        if !item.ifa_name.is_null() && !item.ifa_data.is_null() {
            let name = unsafe { CStr::from_ptr(item.ifa_name) }.to_string_lossy();
            if name == interface {
                let data = unsafe { &*(item.ifa_data as *const libc::if_data) };
                traffic = Some(InterfaceTraffic {
                    rx_bytes: data.ifi_ibytes as u64,
                    tx_bytes: data.ifi_obytes as u64,
                    rx_packets: data.ifi_ipackets as u64,
                    tx_packets: data.ifi_opackets as u64,
                });
                break;
            }
        }
        cursor = item.ifa_next;
    }

    unsafe {
        libc::freeifaddrs(addrs);
    }
    traffic.ok_or_else(|| format!("interface counters not found: {interface}"))
}

pub fn sync_plan(
    interface: &str,
    plan: &NetworkPlan,
    current: Option<&AppliedNetwork>,
) -> Result<AppliedNetwork, String> {
    let Some(current) = current else {
        return apply_plan(interface, plan);
    };
    validate_interface(interface)?;
    if current.interface != interface {
        current.clone().cleanup();
        return apply_plan(interface, plan);
    }

    if current.address != plan.address || current.mtu != plan.mtu {
        configure_interface(interface, plan)?;
    }

    let current_routes = current.routes.iter().copied().collect::<HashSet<_>>();
    let next_routes = plan.routes.iter().copied().collect::<HashSet<_>>();
    let mut added_routes = Vec::new();

    for route in next_routes.difference(&current_routes) {
        if let Err(error) = add_route(route, interface) {
            for added_route in added_routes {
                let _ = delete_route(&added_route);
            }
            return Err(error);
        }
        added_routes.push(*route);
    }

    for route in current_routes.difference(&next_routes) {
        let _ = delete_route(route);
    }

    Ok(AppliedNetwork {
        interface: interface.to_owned(),
        address: plan.address,
        mtu: plan.mtu,
        routes: plan.routes.clone(),
    })
}

pub fn build_plan(
    options: &Value,
    running_info: Option<&Value>,
) -> Result<Option<NetworkPlan>, String> {
    let address = running_info
        .and_then(|info| info.pointer("/my_node_info/virtual_ipv4"))
        .and_then(parse_core_ipv4_cidr)
        .or_else(|| {
            options
                .get("ipv4")
                .and_then(Value::as_str)
                .and_then(parse_ipv4_cidr)
        });

    let Some(address) = address else {
        return Ok(None);
    };

    let mtu = options.get("mtu").and_then(Value::as_u64);
    let mut routes = if let Some(routes) = options
        .get("routes")
        .and_then(Value::as_array)
        .filter(|routes| !routes.is_empty())
    {
        routes
            .iter()
            .filter_map(Value::as_str)
            .filter_map(parse_ipv4_cidr)
            .collect::<HashSet<_>>()
    } else {
        let mut routes = HashSet::new();
        if let Some(core_routes) = running_info
            .and_then(|info| info.get("routes"))
            .and_then(Value::as_array)
        {
            for route in core_routes {
                if let Some(proxy_cidrs) = route.get("proxy_cidrs").and_then(Value::as_array) {
                    for cidr in proxy_cidrs {
                        if let Some(cidr) = cidr.as_str().and_then(parse_ipv4_cidr) {
                            routes.insert(masked(cidr));
                        }
                    }
                }
            }
        }
        if let Some(option_cidr) = options
            .get("ipv4")
            .and_then(Value::as_str)
            .and_then(parse_ipv4_cidr)
        {
            routes.insert(masked(option_cidr));
        }
        routes.insert(masked(address));
        if options
            .get("magicDNS")
            .and_then(Value::as_bool)
            .unwrap_or(false)
        {
            routes.insert(MAGIC_DNS_CIDR);
        }
        routes
    };

    routes.remove(&Ipv4Cidr {
        address: Ipv4Addr::new(0, 0, 0, 0),
        prefix: 0,
    });
    let mut routes = routes.into_iter().collect::<Vec<_>>();
    sort_routes(&mut routes);
    remove_covered_routes(&mut routes);

    Ok(Some(NetworkPlan {
        address,
        mtu,
        routes,
    }))
}

pub fn apply_plan(interface: &str, plan: &NetworkPlan) -> Result<AppliedNetwork, String> {
    validate_interface(interface)?;
    configure_interface(interface, plan)?;

    let mut applied_routes = Vec::new();
    for route in &plan.routes {
        if let Err(error) = add_route(route, interface) {
            for applied_route in applied_routes {
                let _ = delete_route(&applied_route);
            }
            let _ = run(
                IFCONFIG_CANDIDATES,
                "ifconfig",
                &[interface.to_owned(), "down".to_owned()],
            );
            return Err(error);
        }
        applied_routes.push(*route);
    }

    Ok(AppliedNetwork {
        interface: interface.to_owned(),
        address: plan.address,
        mtu: plan.mtu,
        routes: applied_routes,
    })
}

fn configure_interface(interface: &str, plan: &NetworkPlan) -> Result<(), String> {
    let netmask = prefix_to_netmask(plan.address.prefix)?;
    let mut ifconfig_args = vec![
        interface.to_owned(),
        "inet".to_owned(),
        plan.address.address.to_string(),
        plan.address.address.to_string(),
        "netmask".to_owned(),
        netmask.to_string(),
    ];
    if let Some(mtu) = plan.mtu {
        if mtu == 0 || mtu > 9000 {
            return Err(format!("invalid mtu: {mtu}"));
        }
        ifconfig_args.push("mtu".to_owned());
        ifconfig_args.push(mtu.to_string());
    }
    ifconfig_args.push("up".to_owned());
    run(IFCONFIG_CANDIDATES, "ifconfig", &ifconfig_args)
}

fn add_route(route: &Ipv4Cidr, interface: &str) -> Result<(), String> {
    let destination = masked(*route).address.to_string();
    if route.prefix == 32 {
        run(
            ROUTE_CANDIDATES,
            "route",
            &[
                "-n".to_owned(),
                "add".to_owned(),
                "-host".to_owned(),
                destination,
                "-interface".to_owned(),
                interface.to_owned(),
            ],
        )
    } else {
        run(
            ROUTE_CANDIDATES,
            "route",
            &[
                "-n".to_owned(),
                "add".to_owned(),
                "-net".to_owned(),
                destination,
                "-netmask".to_owned(),
                prefix_to_netmask(route.prefix)?.to_string(),
                "-interface".to_owned(),
                interface.to_owned(),
            ],
        )
    }
}

fn delete_route(route: &Ipv4Cidr) -> Result<(), String> {
    let destination = masked(*route).address.to_string();
    if route.prefix == 32 {
        run(
            ROUTE_CANDIDATES,
            "route",
            &[
                "-n".to_owned(),
                "delete".to_owned(),
                "-host".to_owned(),
                destination,
            ],
        )
    } else {
        run(
            ROUTE_CANDIDATES,
            "route",
            &[
                "-n".to_owned(),
                "delete".to_owned(),
                "-net".to_owned(),
                destination,
                "-netmask".to_owned(),
                prefix_to_netmask(route.prefix)?.to_string(),
            ],
        )
    }
}

fn run(candidates: &[&str], command_name: &str, args: &[String]) -> Result<(), String> {
    let program = candidates
        .iter()
        .copied()
        .find(|candidate| Path::new(candidate).is_file())
        .ok_or_else(|| format!("{command_name} not found; tried: {}", candidates.join(", ")))?;
    let output = Command::new(program)
        .args(args)
        .output()
        .map_err(|error| format!("{program} failed to execute: {error}"))?;
    if output.status.success() {
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        Err(format!(
            "{program} {} failed: {}{}",
            args.join(" "),
            stdout,
            stderr
        ))
    }
}

fn parse_core_ipv4_cidr(value: &Value) -> Option<Ipv4Cidr> {
    if let Some(value) = value.as_str() {
        return parse_ipv4_cidr(value);
    }

    let prefix = value.get("network_length")?.as_u64()?;
    let prefix = u8::try_from(prefix).ok()?;
    let raw_addr = value.pointer("/address/addr")?.as_u64()?;
    let raw_addr = u32::try_from(raw_addr).ok()?;
    Some(Ipv4Cidr {
        address: Ipv4Addr::from(raw_addr),
        prefix,
    })
    .filter(|cidr| cidr.prefix <= 32)
}

fn parse_ipv4_cidr(value: &str) -> Option<Ipv4Cidr> {
    let (address, prefix) = value.split_once('/').unwrap_or((value, "32"));
    let address = address.parse::<Ipv4Addr>().ok()?;
    let prefix = prefix.parse::<u8>().ok()?;
    if prefix <= 32 {
        Some(Ipv4Cidr { address, prefix })
    } else {
        None
    }
}

fn masked(cidr: Ipv4Cidr) -> Ipv4Cidr {
    let mask = if cidr.prefix == 0 {
        0
    } else {
        u32::MAX << (32 - cidr.prefix)
    };
    Ipv4Cidr {
        address: Ipv4Addr::from(u32::from(cidr.address) & mask),
        prefix: cidr.prefix,
    }
}

fn remove_covered_routes(routes: &mut Vec<Ipv4Cidr>) {
    let mut remove = HashSet::new();
    for i in 0..routes.len() {
        if remove.contains(&i) {
            continue;
        }
        for j in (i + 1)..routes.len() {
            if remove.contains(&j) {
                continue;
            }
            if route_covers(routes[i], routes[j]) {
                remove.insert(j);
            }
        }
    }
    let mut remove = remove.into_iter().collect::<Vec<_>>();
    remove.sort_by(|left, right| right.cmp(left));
    for index in remove {
        routes.remove(index);
    }
}

fn sort_routes(routes: &mut [Ipv4Cidr]) {
    routes.sort_by_key(|route| (route.prefix, u32::from(route.address)));
}

fn route_covers(bigger: Ipv4Cidr, smaller: Ipv4Cidr) -> bool {
    bigger.prefix <= smaller.prefix
        && masked(Ipv4Cidr {
            address: smaller.address,
            prefix: bigger.prefix,
        })
        .address
            == masked(bigger).address
}

fn prefix_to_netmask(prefix: u8) -> Result<Ipv4Addr, String> {
    if prefix > 32 {
        return Err(format!("invalid ipv4 prefix: {prefix}"));
    }
    let mask = if prefix == 0 {
        0
    } else {
        u32::MAX << (32 - prefix)
    };
    Ok(Ipv4Addr::from(mask))
}

fn validate_interface(interface: &str) -> Result<(), String> {
    if !interface.starts_with("utun")
        || interface.is_empty()
        || !interface.chars().all(|char| char.is_ascii_alphanumeric())
    {
        return Err(format!("invalid interface name: {interface}"));
    }
    Ok(())
}

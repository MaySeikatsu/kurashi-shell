//! Whether the figures are this machine's own (docs/ux/sysmon.md, States: "VM/container: label 'host values'").
//! In a container `/proc` shows the whole host unless the runtime masks it, so the CPU and memory figures
//! are the host's; in a virtual machine the sensors belong to the hypervisor. The panel says so either way.
//! Read once per enable: nothing here changes while the daemon runs.

use crate::roots::Roots;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Host {
    Bare,
    Container,
    Vm,
}

impl Host {
    /// The name the documents carry: `null` on a bare machine, `container` or `vm` otherwise.
    pub fn name(self) -> Option<&'static str> {
        match self {
            Host::Bare => None,
            Host::Container => Some("container"),
            Host::Vm => Some("vm"),
        }
    }
}

/// Cgroup path fragments that only a container runtime creates (PID 1's cgroup names the runtime).
const CONTAINER_CGROUPS: [&str; 5] = ["docker", "lxc", "kubepods", "libpod", "containerd"];

pub fn detect(roots: &Roots) -> Host {
    let cgroup = roots.read(roots.proc.join("1/cgroup")).unwrap_or_default();
    if CONTAINER_CGROUPS.iter().any(|m| cgroup.contains(m)) {
        return Host::Container;
    }
    // x86 guests carry the `hypervisor` CPU flag; the flags line is the same on every core.
    let cpuinfo = roots.read(roots.proc.join("cpuinfo")).unwrap_or_default();
    let guest = cpuinfo
        .lines()
        .find(|l| l.starts_with("flags"))
        .is_some_and(|l| l.split_whitespace().any(|f| f == "hypervisor"));
    if guest { Host::Vm } else { Host::Bare }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn proc_tree(cgroup: &str, cpuinfo: &str) -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("proc/1")).unwrap();
        std::fs::write(dir.path().join("proc/1/cgroup"), cgroup).unwrap();
        std::fs::write(dir.path().join("proc/cpuinfo"), cpuinfo).unwrap();
        dir
    }

    fn roots(dir: &tempfile::TempDir) -> Roots {
        Roots::new(dir.path().join("proc"), dir.path().join("sys"), 1000)
    }

    #[test]
    fn a_bare_machine_has_no_host_label() {
        let dir = proc_tree("0::/init.scope\n", "flags\t\t: fpu vme sse4_2 aes\n");
        assert_eq!(detect(&roots(&dir)), Host::Bare);
        assert_eq!(Host::Bare.name(), None);
    }

    #[test]
    fn a_container_runtime_in_pid_one_makes_it_a_container() {
        let dir = proc_tree(
            "12:devices:/docker/3f2a\n0::/system.slice/containerd.service\n",
            "",
        );
        assert_eq!(detect(&roots(&dir)), Host::Container);
        assert_eq!(Host::Container.name(), Some("container"));
    }

    #[test]
    fn the_hypervisor_flag_makes_it_a_vm_and_only_on_the_flags_line() {
        let dir = proc_tree(
            "0::/init.scope\n",
            "model name\t: hypervisor-ish cpu\nflags\t\t: fpu hypervisor\n",
        );
        assert_eq!(detect(&roots(&dir)), Host::Vm);
        let dir = proc_tree(
            "0::/init.scope\n",
            "model name\t: hypervisor cpu\nflags\t\t: fpu\n",
        );
        assert_eq!(
            detect(&roots(&dir)),
            Host::Bare,
            "the word in the model name is not the flag"
        );
    }

    #[test]
    fn a_missing_proc_is_a_bare_machine_not_a_guess() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(
            detect(&Roots::new(
                dir.path().join("proc"),
                dir.path().join("sys"),
                1000
            )),
            Host::Bare
        );
    }
}

Name:           quill-snapshots
Version:        44
Release:        1%{?dist}
Summary:        Btrfs snapshots around package transactions, and rollback
License:        GPL-3.0-or-later
URL:            https://quill-os.example/
BuildArch:      noarch

Source1:        quill-snapper.actions
Source2:        quill-snapshot
Source3:        quill-snapshots-setup
Source4:        quill-snapshots-setup.service
Source5:        80-quill-snapshots.preset
Source6:        quill.template
Source7:        quill-rollback
Source8:        README.md

BuildRequires:  systemd-rpm-macros

Requires:       snapper
Requires:       libdnf5-plugin-actions
Requires:       btrfs-progs
Requires:       util-linux
Requires:       coreutils >= 9.5
Requires:       grub2-tools
Requires:       procps-ng
%{?systemd_requires}

%description
Quill OS takes a snapper snapshot of the root filesystem before and after
every package transaction, whether it runs through dnf, Discover or Quill
Setup, and provides quill-rollback to make an earlier snapshot the running
system. /home and /boot are not snapshotted.


%prep


%build


%install
install -Dpm 0644 %{SOURCE1} %{buildroot}%{_sysconfdir}/dnf/libdnf5-plugins/actions.d/quill-snapper.actions
install -Dpm 0755 %{SOURCE2} %{buildroot}%{_libexecdir}/quill-snapshot
install -Dpm 0755 %{SOURCE3} %{buildroot}%{_libexecdir}/quill-snapshots-setup
install -Dpm 0644 %{SOURCE4} %{buildroot}%{_unitdir}/quill-snapshots-setup.service
install -Dpm 0644 %{SOURCE5} %{buildroot}%{_presetdir}/80-quill-snapshots.preset
install -Dpm 0644 %{SOURCE6} %{buildroot}%{_datadir}/snapper/config-templates/quill
install -Dpm 0755 %{SOURCE7} %{buildroot}%{_bindir}/quill-rollback
install -Dpm 0644 %{SOURCE8} %{buildroot}%{_docdir}/%{name}/README.md


%check
sh -n %{SOURCE2}
sh -n %{SOURCE3}
bash -n %{SOURCE7}
# Two actions, both host-only, so image builds (--installroot) never snapshot.
# Five colon-separated items: callback:filter:direction:options:command.
test "$(grep -c '^[a-z_]*_transaction:::enabled=host-only:/usr/libexec/quill-snapshot ' %{SOURCE1})" = 2
grep -qx 'TIMELINE_CREATE="no"' %{SOURCE6}


%post
# snapper's own timers are listed too: snapper is usually installed in the same
# transaction, before this package, so its scriptlet ran before our preset
# existed. Presetting them here applies 80-quill-snapshots.preset to them.
%systemd_post quill-snapshots-setup.service snapper-cleanup.timer snapper-timeline.timer snapper-boot.timer

%preun
%systemd_preun quill-snapshots-setup.service


%files
%config(noreplace) %{_sysconfdir}/dnf/libdnf5-plugins/actions.d/quill-snapper.actions
%{_libexecdir}/quill-snapshot
%{_libexecdir}/quill-snapshots-setup
%{_unitdir}/quill-snapshots-setup.service
%{_presetdir}/80-quill-snapshots.preset
%{_datadir}/snapper/config-templates/quill
%{_bindir}/quill-rollback
%{_docdir}/%{name}/README.md


%changelog
* Sat Oct 31 2026 Quill OS Maintainers <maintainers@quill-os.example> - 44-1
- Snapshots around package transactions, first-boot snapper setup, quill-rollback

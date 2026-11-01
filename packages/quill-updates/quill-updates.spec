Name:           quill-updates
Version:        44
Release:        1%{?dist}
Summary:        Background download of system and Flatpak updates
License:        GPL-3.0-or-later
URL:            https://quill-os.example/
BuildArch:      noarch

Source1:        quill-update-download
Source2:        quill-update-download.service
Source3:        quill-update-download.timer
Source4:        80-quill-updates.preset
Source5:        PlasmaDiscoverUpdates
Source6:        README.md

BuildRequires:  systemd-rpm-macros

Requires:       PackageKit
Requires:       plasma-discover-notifier
Requires:       plasma-discover-offline-updates
Requires:       systemd
%{?systemd_requires}

%description
Downloads system updates (through PackageKit, which Discover uses) and Flatpak
updates once a day, skipping metered connections and battery power. It
installs nothing: Discover notifies about the updates and applies them on the
next reboot.


%prep


%build


%install
install -Dpm 0755 %{SOURCE1} %{buildroot}%{_libexecdir}/quill-update-download
install -Dpm 0644 %{SOURCE2} %{buildroot}%{_unitdir}/quill-update-download.service
install -Dpm 0644 %{SOURCE3} %{buildroot}%{_unitdir}/quill-update-download.timer
install -Dpm 0644 %{SOURCE4} %{buildroot}%{_presetdir}/80-quill-updates.preset
install -Dpm 0644 %{SOURCE5} %{buildroot}%{_sysconfdir}/xdg/PlasmaDiscoverUpdates
install -Dpm 0644 %{SOURCE6} %{buildroot}%{_docdir}/%{name}/README.md


%check
sh -n %{SOURCE1}
# Download only: nothing that installs, deploys or schedules an offline update.
# (rpmbuild runs this under set -e, which ignores "! cmd", hence the ifs.)
grep -v '^[[:space:]]*#' %{SOURCE1} > code.sh
if grep -Eq 'offline-trigger|(pkcon|(^|[^a-z])pk) .*install' code.sh; then exit 1; fi
# The update call exists (so the next check is not vacuous) and only downloads.
grep -Eq '(^|[^a-z])pk --only-download update' code.sh
if grep -Eo '(pkcon|(^|[^a-z])pk) [^;&|)]*update' code.sh | grep -qv -- --only-download; then exit 1; fi
if grep 'flatpak update' code.sh | grep -qv -- --no-deploy; then exit 1; fi

%post
%systemd_post quill-update-download.timer

%preun
%systemd_preun quill-update-download.timer

%postun
%systemd_postun quill-update-download.timer


%files
%{_libexecdir}/quill-update-download
%{_unitdir}/quill-update-download.service
%{_unitdir}/quill-update-download.timer
%{_presetdir}/80-quill-updates.preset
%config(noreplace) %{_sysconfdir}/xdg/PlasmaDiscoverUpdates
%{_docdir}/%{name}/README.md


%changelog
* Sat Oct 31 2026 Quill OS Maintainers <maintainers@quill-os.example> - 44-1
- Daily background download of updates; Discover notifies and applies them

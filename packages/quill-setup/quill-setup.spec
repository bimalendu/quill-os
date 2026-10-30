Name:           quill-setup
Version:        44
Release:        1%{?dist}
Summary:        First-login software selection for Quill OS
License:        GPL-3.0-or-later
URL:            https://quill-os.example/
# make rpms builds this tarball from src/ (see the Makefile).
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  desktop-file-utils
BuildRequires:  python3

Requires:       qt6-qtdeclarative
Requires:       kf6-kirigami
Requires:       kf6-qqc2-desktop-style
Requires:       polkit
Requires:       python3
Requires:       dnf5
Requires:       flatpak
Requires:       quill-logos

%description
Quill Setup lets the user choose extra software groups (developer tools, office,
audio and video, graphics, gaming) on first login, and again later from the
application menu. A privileged helper, run through polkit, installs the chosen
groups. The interface names groups only; the package names live in root-owned
definition files, so the interface cannot ask for arbitrary software.

%prep
%autosetup -n %{name}-%{version}

%build
%cmake -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/quill-setup.desktop
desktop-file-validate %{buildroot}%{_sysconfdir}/xdg/autostart/quill-setup.desktop
test -x %{buildroot}%{_libexecdir}/quill-setup-helper

%files
%{_bindir}/quill-setup
%{_libexecdir}/quill-setup-helper
%{_datadir}/quill-setup/
%{_datadir}/polkit-1/actions/org.quill.setup.policy
%{_datadir}/applications/quill-setup.desktop
%config(noreplace) %{_sysconfdir}/xdg/autostart/quill-setup.desktop

%changelog
* Fri Oct 30 2026 Quill OS Maintainers <maintainers@quill-os.example> - 44-1
- Initial Quill Setup: group picker, polkit helper and first-login autostart

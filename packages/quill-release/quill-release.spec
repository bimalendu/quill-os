# Quill OS release files.
#
# Derived from the Fedora Asahi Remix release spec
# (pagure.io/fedora-asahi/fedora-asahi-remix-release, itself derived from
# Fedora's fedora-release, MIT licensed), cut down to the two variants Quill
# ships: the KDE Plasma desktop and the basic (minimal) image.
#
# The package splits mirror Fedora's so that anything that requires
# fedora-release, fedora-release-common or system-release is still satisfied.

# No %%dist in the release of this package, as in Fedora's release packages.
%global dist %{nil}

# Fedora release this Quill OS release is based on. Quill's version tracks it.
%global dist_version 44

# Identity. Placeholder URLs until the project has a real domain.
%global dist_vendor Quill OS
%global dist_name   Quill OS
%global dist_home_url https://quill-os.example/
%global dist_bug_report_url https://quill-os.example/bugs
%global dist_docs_url https://quill-os.example/docs
%global dist_support_url https://quill-os.example/support
# Fedora's debuginfod serves the Fedora packages Quill is built from.
%global dist_debuginfod_url ima:enforcing https://debuginfod.fedoraproject.org/ ima:ignore
# The namespace for purl; packages are Fedora's.
%global dist_purl_namespace fedora

Summary:        Quill OS release files
Name:           quill-release
Version:        %{dist_version}
Release:        1
License:        MIT
URL:            %{dist_home_url}
BuildArch:      noarch

Source1:        LICENSE
Source2:        Quill-Legal-README.txt
Source10:       85-display-manager.preset
Source11:       90-default.preset
Source12:       90-default-user.preset
Source13:       99-default-disable.preset
Source26:       80-kde-desktop.preset
Source27:       81-desktop.preset
Source25:       plasma-desktop.conf
Source31:       20-quill-defaults.conf

BuildRequires:  redhat-rpm-config > 121-1
BuildRequires:  systemd-rpm-macros

Provides:       quill-release-variant = %{version}-%{release}
Provides:       system-release
Provides:       system-release(%{version})
Requires:       quill-release-common = %{version}-%{release}

# Pulls in the basic identity if nothing else provides an identity.
Recommends:     quill-release-identity-basic

# We replace the Fedora and Fedora Asahi Remix release packages.
Conflicts:      fedora-release < 1:%{version}-%{release}
Conflicts:      fedora-release-identity
Conflicts:      fedora-asahi-remix-release
Obsoletes:      fedora-release < 1:%{version}-%{release}
Provides:       fedora-release = 1:%{version}-%{release}

%description
Quill OS release files such as the /etc files that define the release and the
systemd preset files that determine which services are enabled by default.
See https://docs.fedoraproject.org/en-US/packaging-guidelines/DefaultServices/
for details.


%package common
Summary:        Quill OS release files common to all variants

Requires:       quill-release-variant = %{version}-%{release}
Suggests:       quill-release
Requires:       fedora-repos(%{version})
Requires:       quill-release-identity = %{version}-%{release}

Obsoletes:      fedora-release-common < 1:%{version}-%{release}
Provides:       fedora-release-common = 1:%{version}-%{release}

# Fedora's generic-release cannot coexist with a distribution-specific release.
Conflicts:      generic-release
Conflicts:      fedora-asahi-remix-release-common

# rpm-ostree count me is enabled in 90-default.preset
Obsoletes:      fedora-release-ostree-counting <= 36-0.7

%description common
Release files common to all Quill OS variants.


%package identity-basic
Summary:        Package providing the identity for Quill OS (basic)

RemovePathPostfixes: .basic
Provides:       quill-release-identity = %{version}-%{release}
Conflicts:      quill-release-identity
Conflicts:      fedora-asahi-remix-release-identity

%description identity-basic
Provides the necessary files for an installation that identifies itself as
Quill OS without a desktop variant.


%package kde-desktop
Summary:        Base package for Quill OS KDE Plasma default configuration

RemovePathPostfixes: .kde-desktop
Provides:       quill-release = %{version}-%{release}
Provides:       quill-release-variant = %{version}-%{release}
Provides:       system-release
Provides:       system-release(%{version})
Requires:       quill-release-common = %{version}-%{release}

Obsoletes:      fedora-release-kde < 1:%{version}-%{release}
Provides:       fedora-release-kde = 1:%{version}-%{release}
Provides:       fedora-release = 1:%{version}-%{release}
Conflicts:      fedora-asahi-remix-release-kde-desktop

# quill-release-common requires an identity; this pulls in the KDE one if
# nothing else provides it.
Recommends:     quill-release-identity-kde-desktop

%description kde-desktop
Base package for Quill OS KDE Plasma configuration files to depend on, and the
KDE Plasma system defaults.


%package identity-kde-desktop
Summary:        Package providing the identity for Quill OS (KDE Plasma)

RemovePathPostfixes: .kde-desktop
Provides:       quill-release-identity = %{version}-%{release}
Conflicts:      quill-release-identity
Conflicts:      fedora-asahi-remix-release-identity
Requires(meta): quill-release-kde-desktop = %{version}-%{release}

Obsoletes:      fedora-release-identity-kde < 1:%{version}-%{release}
Provides:       fedora-release-identity-kde = 1:%{version}-%{release}

%description identity-kde-desktop
Provides the necessary files for an installation that identifies itself as
Quill OS with the KDE Plasma desktop.


%prep
mkdir -p licenses
sed 's|@@VERSION@@|%{dist_version}|g' %{SOURCE2} > licenses/Quill-Legal-README.txt


%build


%install
install -d %{buildroot}%{_prefix}/lib
echo "Quill OS release %{version} (based on Fedora Linux %{dist_version})" > %{buildroot}%{_prefix}/lib/quill-release
echo "cpe:/o:quill-os:quill-os:%{version}" > %{buildroot}%{_prefix}/lib/system-release-cpe

# Symlink the -release files. fedora-release and redhat-release are kept
# because tools in the Fedora package set look for them.
install -d %{buildroot}%{_sysconfdir}
ln -s ../usr/lib/quill-release %{buildroot}%{_sysconfdir}/quill-release
ln -s ../usr/lib/system-release-cpe %{buildroot}%{_sysconfdir}/system-release-cpe
ln -s quill-release %{buildroot}%{_sysconfdir}/fedora-release
ln -s quill-release %{buildroot}%{_sysconfdir}/redhat-release
ln -s quill-release %{buildroot}%{_sysconfdir}/system-release

# The os-release template. ID_LIKE=fedora keeps Fedora-aware tooling working.
# The REDHAT_BUGZILLA_* fields are left out on purpose: they would route bug
# reports to Fedora's Bugzilla.
cat <<EOF >os-release
NAME="%{dist_name}"
VERSION="%{dist_version}"
RELEASE_TYPE=stable
ID=quill
ID_LIKE=fedora
VERSION_ID=%{dist_version}
PRETTY_NAME="%{dist_name} %{dist_version}"
ANSI_COLOR="0;38;2;75;74;207"
LOGO=quill-logo-icon
CPE_NAME="cpe:/o:quill-os:quill-os:%{dist_version}"
DEFAULT_HOSTNAME="quill"
HOME_URL="%{dist_home_url}"
DOCUMENTATION_URL="%{dist_docs_url}"
SUPPORT_URL="%{dist_support_url}"
BUG_REPORT_URL="%{dist_bug_report_url}"
EOF

# Basic (minimal) identity
cp -p os-release %{buildroot}%{_prefix}/lib/os-release.basic

# KDE Plasma identity. VARIANT_ID=kde is the value Fedora's KDE spin uses and
# third-party tooling checks for.
cp -p os-release %{buildroot}%{_prefix}/lib/os-release.kde-desktop
echo 'VARIANT="KDE Plasma"' >> %{buildroot}%{_prefix}/lib/os-release.kde-desktop
echo 'VARIANT_ID=kde' >> %{buildroot}%{_prefix}/lib/os-release.kde-desktop
sed -i -e 's|^VERSION="%{dist_version}"|VERSION="%{dist_version} (KDE Plasma)"|' \
       -e 's|^PRETTY_NAME=".*"|PRETTY_NAME="%{dist_name} %{dist_version} (KDE Plasma)"|' \
       %{buildroot}%{_prefix}/lib/os-release.kde-desktop

# Add plasma-desktop to the dnf protected packages list
install -Dm0644 %{SOURCE25} -t %{buildroot}%{_sysconfdir}/dnf/protected.d/
install -Dm0644 %{SOURCE26} -t %{buildroot}%{_prefix}/lib/systemd/system-preset/
install -Dm0644 %{SOURCE27} -t %{buildroot}%{_prefix}/lib/systemd/system-preset/

# /etc/os-release
ln -s ../usr/lib/os-release %{buildroot}%{_sysconfdir}/os-release

# /etc/issue, /etc/issue.net and /etc/issue.d
echo "\S" > %{buildroot}%{_prefix}/lib/issue
echo "Kernel \r on \m (\l)" >> %{buildroot}%{_prefix}/lib/issue
echo >> %{buildroot}%{_prefix}/lib/issue
ln -s ../usr/lib/issue %{buildroot}%{_sysconfdir}/issue
echo "\S" > %{buildroot}%{_prefix}/lib/issue.net
echo "Kernel \r on \m (\l)" >> %{buildroot}%{_prefix}/lib/issue.net
ln -s ../usr/lib/issue.net %{buildroot}%{_sysconfdir}/issue.net
mkdir -p %{buildroot}%{_sysconfdir}/issue.d

# Dist tag macros. The distribution still builds Fedora packages, so the
# %%fedora, %%fc44 and %%dist macros must keep their Fedora values.
install -d -m 755 %{buildroot}%{_rpmconfigdir}/macros.d
cat >> %{buildroot}%{_rpmconfigdir}/macros.d/macros.dist << EOF
# dist macros.

%%__bootstrap         ~bootstrap
%%fedora              %{dist_version}
%%fc%{dist_version}                1
%%distcore            .fc%%{fedora}
%%dist                %%{!?distprefix0:%%{?distprefix}}%%{expand:%%{lua:for i=0,9999 do print("%%{?distprefix" .. i .."}") end}}%%{distcore}%%{?with_bootstrap}
%%dist_vendor         %{dist_vendor}
%%dist_name           %{dist_name}
%%dist_purl_namespace %{dist_purl_namespace}
%%dist_home_url       %{dist_home_url}
%%dist_bug_report_url %{dist_bug_report_url}
%%dist_debuginfod_url %{dist_debuginfod_url}
EOF

# Default services
install -Dm0644 %{SOURCE10} -t %{buildroot}%{_prefix}/lib/systemd/system-preset/
install -Dm0644 %{SOURCE11} -t %{buildroot}%{_prefix}/lib/systemd/system-preset/
install -Dm0644 %{SOURCE12} -t %{buildroot}%{_prefix}/lib/systemd/user-preset/
# The same file is installed in two places with identical contents
install -Dm0644 %{SOURCE13} -t %{buildroot}%{_prefix}/lib/systemd/system-preset/
install -Dm0644 %{SOURCE13} -t %{buildroot}%{_prefix}/lib/systemd/user-preset/

# DNF 5 defaults
install -Dm0644 %{SOURCE31} -t %{buildroot}%{_prefix}/share/dnf5/libdnf.conf.d/

# COPR vendor file: users enable Fedora COPR projects against Fedora releases.
install -d %{buildroot}%{_datadir}/dnf/plugins
cat >> %{buildroot}%{_datadir}/dnf/plugins/copr.vendor.conf << EOF
[main]
distribution = fedora
releasever = %{dist_version}
EOF

install -pm 0644 %{SOURCE1} licenses/LICENSE


%check
# The two os-release variants must parse as shell and carry the identity.
for f in %{buildroot}%{_prefix}/lib/os-release.basic %{buildroot}%{_prefix}/lib/os-release.kde-desktop; do
    (. "$f"; test "$ID" = quill && test "$ID_LIKE" = fedora && test "$VERSION_ID" = "%{dist_version}")
done


%files
%license licenses/LICENSE


%files common
%license licenses/LICENSE licenses/Quill-Legal-README.txt
%{_prefix}/lib/quill-release
%{_prefix}/lib/system-release-cpe
%{_sysconfdir}/os-release
%{_sysconfdir}/quill-release
%{_sysconfdir}/fedora-release
%{_sysconfdir}/redhat-release
%{_sysconfdir}/system-release
%{_sysconfdir}/system-release-cpe
%attr(0644,root,root) %{_prefix}/lib/issue
%config(noreplace) %{_sysconfdir}/issue
%attr(0644,root,root) %{_prefix}/lib/issue.net
%config(noreplace) %{_sysconfdir}/issue.net
%dir %{_sysconfdir}/issue.d
%attr(0644,root,root) %{_rpmconfigdir}/macros.d/macros.dist
%dir %{_prefix}/lib/systemd/user-preset/
%{_prefix}/lib/systemd/user-preset/90-default-user.preset
%{_prefix}/lib/systemd/user-preset/99-default-disable.preset
%dir %{_prefix}/lib/systemd/system-preset/
%{_prefix}/lib/systemd/system-preset/85-display-manager.preset
%{_prefix}/lib/systemd/system-preset/90-default.preset
%{_prefix}/lib/systemd/system-preset/99-default-disable.preset
%{_prefix}/share/dnf5/libdnf.conf.d/20-quill-defaults.conf
%dir %{_datadir}/dnf/plugins
%{_datadir}/dnf/plugins/copr.vendor.conf


%files identity-basic
%{_prefix}/lib/os-release.basic


%files kde-desktop
%{_prefix}/lib/systemd/system-preset/80-kde-desktop.preset
%{_prefix}/lib/systemd/system-preset/81-desktop.preset
%{_sysconfdir}/dnf/protected.d/plasma-desktop.conf


%files identity-kde-desktop
%{_prefix}/lib/os-release.kde-desktop


%changelog
* Fri Oct 30 2026 Quill OS Maintainers <maintainers@quill-os.example> - 44-1
- Initial Quill OS release package, derived from fedora-asahi-remix-release

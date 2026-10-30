Name:           quill-plasma-theme
Version:        44
Release:        1%{?dist}
Summary:        Quill OS look and feel for KDE Plasma
# The colour schemes are derived from KDE's Breeze schemes, the look-and-feel
# layout from Fedora's plasma-lookandfeel-fedora.
License:        GPL-2.0-or-later
URL:            https://quill-os.example/
BuildArch:      noarch

Source1:        QuillLight.colors
Source2:        QuillDark.colors
Source3:        laf-light-metadata.json
Source4:        laf-light-defaults
Source5:        laf-dark-metadata.json
Source6:        laf-dark-defaults
Source7:        laf-layout.js
Source8:        kdeglobals
Source9:        kscreenlockerrc
Source10:       plasmalogin-defaults.conf
Source11:       make-color-schemes.py

BuildRequires:  python3

Requires:       plasma-workspace
Requires:       breeze-icon-theme
Requires:       quill-logos
Requires:       quill-backgrounds-kde

# Quill ships the login screen defaults itself, with its own wallpaper.
Conflicts:      kde-settings-plasmalogin

%description
The Quill OS look and feel for KDE Plasma: Quill Light and Quill Dark colour
schemes with the Quill accent, two look-and-feel packages, the system defaults
that select them over Fedora's, and the login and lock screen wallpaper.


%prep


%build


%install
install -Dpm 0644 %{SOURCE1} %{buildroot}%{_datadir}/color-schemes/QuillLight.colors
install -Dpm 0644 %{SOURCE2} %{buildroot}%{_datadir}/color-schemes/QuillDark.colors

laf=%{buildroot}%{_datadir}/plasma/look-and-feel
install -Dpm 0644 %{SOURCE3} $laf/org.quill.desktop/metadata.json
install -Dpm 0644 %{SOURCE4} $laf/org.quill.desktop/contents/defaults
install -Dpm 0644 %{SOURCE7} $laf/org.quill.desktop/contents/layouts/org.kde.plasma.desktop-layout.js
install -Dpm 0644 %{SOURCE5} $laf/org.quill.dark.desktop/metadata.json
install -Dpm 0644 %{SOURCE6} $laf/org.quill.dark.desktop/contents/defaults
install -Dpm 0644 %{SOURCE7} $laf/org.quill.dark.desktop/contents/layouts/org.kde.plasma.desktop-layout.js

# /etc/xdg is searched before Fedora's kde-settings profile directory.
install -Dpm 0644 %{SOURCE8} %{buildroot}%{_sysconfdir}/xdg/kdeglobals
install -Dpm 0644 %{SOURCE9} %{buildroot}%{_sysconfdir}/xdg/kscreenlockerrc

install -Dpm 0644 %{SOURCE10} %{buildroot}%{_prefix}/lib/plasmalogin/defaults.conf


%check
# The look-and-feel metadata must be valid JSON with the expected ids.
python3 - <<'PY'
import json, sys
for path, ident in (("%{SOURCE3}", "org.quill.desktop"), ("%{SOURCE5}", "org.quill.dark.desktop")):
    assert json.load(open(path))["KPlugin"]["Id"] == ident, path
PY
# No Breeze blue may survive in the derived colour schemes.
! grep -q '61,174,233' %{SOURCE1} %{SOURCE2}


%files
%{_datadir}/color-schemes/QuillLight.colors
%{_datadir}/color-schemes/QuillDark.colors
%{_datadir}/plasma/look-and-feel/org.quill.desktop/
%{_datadir}/plasma/look-and-feel/org.quill.dark.desktop/
%config(noreplace) %{_sysconfdir}/xdg/kdeglobals
%config(noreplace) %{_sysconfdir}/xdg/kscreenlockerrc
%{_prefix}/lib/plasmalogin/defaults.conf


%changelog
* Fri Oct 30 2026 Quill OS Maintainers <maintainers@quill-os.example> - 44-1
- Initial Quill OS Plasma theme

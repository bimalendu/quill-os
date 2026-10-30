Name:           quill-logos
Version:        44
Release:        1%{?dist}
Summary:        Quill OS icons and pixmaps
# Placeholder artwork drawn for the project. Change when final artwork exists.
License:        CC-BY-SA-4.0
URL:            https://quill-os.example/
BuildArch:      noarch

Source1:        quill-mark.svg
Source2:        quill-glyph-white.svg

BuildRequires:  librsvg2-tools

# Satisfies what the Fedora KDE and Plymouth packages require (system-logos),
# as Fedora's own generic-logos does.
Provides:       system-logos = %{version}-%{release}
Provides:       redhat-logos = %{version}-%{release}

# Quill OS does not ship the Fedora logos (Fedora trademark rules).
Conflicts:      fedora-logos
Conflicts:      generic-logos
Obsoletes:      fedora-logos < %{version}
Obsoletes:      generic-logos < %{version}

%description
Quill OS logos: the Quill mark as application and start-menu icons, the white
glyph used as a boot splash watermark, and the source SVGs.


%prep


%build
# Dark-on-light variant of the glyph, for light backgrounds.
sed 's/#FFFFFF/#4B4ACF/g' %{SOURCE2} > quill-glyph-indigo.svg

for n in 16 22 24 32 36 48 64 96 128 256; do
    mkdir -p icons/${n}x${n}
    rsvg-convert -w $n -h $n %{SOURCE1} -o icons/${n}x${n}/quill-logo-icon.png
done
mkdir -p pixmaps
rsvg-convert -w 128 -h 128 %{SOURCE1} -o pixmaps/quill-logo.png
rsvg-convert -w 64  -h 64  %{SOURCE1} -o pixmaps/quill-logo-small.png
# Plymouth's spinner theme and KDE's "About this system" use this as the logo.
rsvg-convert -w 192 -h 192 %{SOURCE2} -o pixmaps/system-logo-white.png


%install
install -d %{buildroot}%{_datadir}/quill-logos
install -pm 0644 %{SOURCE1} %{buildroot}%{_datadir}/quill-logos/quill_logo.svg
install -pm 0644 %{SOURCE2} %{buildroot}%{_datadir}/quill-logos/quill_logo_white.svg
install -pm 0644 quill-glyph-indigo.svg %{buildroot}%{_datadir}/quill-logos/quill_logo_indigo.svg

for n in 16 22 24 32 36 48 64 96 128 256; do
    d=%{buildroot}%{_datadir}/icons/hicolor/${n}x${n}
    install -Dpm 0644 icons/${n}x${n}/quill-logo-icon.png $d/apps/quill-logo-icon.png
    # The launcher button on the panel uses the generic start-here icon.
    install -Dpm 0644 icons/${n}x${n}/quill-logo-icon.png $d/places/start-here.png
done
install -Dpm 0644 %{SOURCE1} %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/quill-logo-icon.svg
install -Dpm 0644 %{SOURCE1} %{buildroot}%{_datadir}/icons/hicolor/scalable/places/start-here.svg

install -Dpm 0644 pixmaps/quill-logo.png %{buildroot}%{_datadir}/pixmaps/quill-logo.png
install -Dpm 0644 pixmaps/quill-logo-small.png %{buildroot}%{_datadir}/pixmaps/quill-logo-small.png
install -Dpm 0644 pixmaps/system-logo-white.png %{buildroot}%{_datadir}/pixmaps/system-logo-white.png


%files
%{_datadir}/quill-logos/
%{_datadir}/icons/hicolor/*/apps/quill-logo-icon.*
%{_datadir}/icons/hicolor/*/places/start-here.*
%{_datadir}/pixmaps/quill-logo.png
%{_datadir}/pixmaps/quill-logo-small.png
%{_datadir}/pixmaps/system-logo-white.png


%changelog
* Fri Oct 30 2026 Quill OS Maintainers <maintainers@quill-os.example> - 44-1
- Initial Quill OS logos package with placeholder artwork

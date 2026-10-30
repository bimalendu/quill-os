Name:           quill-backgrounds-kde
Version:        44
Release:        1%{?dist}
Summary:        Quill OS default wallpaper for KDE Plasma
License:        CC-BY-SA-4.0
URL:            https://quill-os.example/
BuildArch:      noarch

Source1:        gen-wallpaper.sh

BuildRequires:  librsvg2-tools
BuildRequires:  ImageMagick
BuildRequires:  gawk

# Fedora's KDE packages (kde-settings-plasma, plasma-setup, ...) require this.
Provides:       system-backgrounds-kde = %{version}-%{release}
Conflicts:      desktop-backgrounds-kde
Conflicts:      f44-backgrounds-kde

%description
The default Quill OS wallpaper as a Plasma wallpaper package, with a light and
a dark variant at the common Apple Silicon display sizes. The images are
generated at build time from a script (gen-wallpaper.sh).


%prep


%build
# 16:10 (MacBook Air and Pro) and 16:9 (external displays). Plasma picks the
# closest match and scales.
sizes="1920x1200 2560x1600 3456x2160 1920x1080 3840x2160"
for variant in light dark; do
    mkdir -p $variant
    for size in $sizes; do
        w=${size%x*}; h=${size#*x}
        sh %{SOURCE1} $variant $w $h > $variant/$size.svg
        rsvg-convert $variant/$size.svg -o $variant/$size.png
        # A little noise breaks up the banding of the smooth gradients.
        magick $variant/$size.png -attenuate 0.25 +noise Gaussian -quality 88 $variant/$size.jpg
    done
done

cat > metadata.json <<JSON
{
    "KPackageStructure": "Wallpaper/Images",
    "KPlugin": {
        "Authors": [{"Name": "Quill OS"}],
        "Id": "Quill",
        "License": "CC-BY-SA-4.0",
        "Name": "Quill"
    }
}
JSON


%install
d=%{buildroot}%{_datadir}/wallpapers/Quill
install -Dpm 0644 metadata.json $d/metadata.json
for f in light/*.jpg; do install -Dpm 0644 $f $d/contents/images/$(basename $f); done
for f in dark/*.jpg;  do install -Dpm 0644 $f $d/contents/images_dark/$(basename $f); done


%files
%{_datadir}/wallpapers/Quill/


%changelog
* Fri Oct 30 2026 Quill OS Maintainers <maintainers@quill-os.example> - 44-1
- Initial Quill OS wallpaper package

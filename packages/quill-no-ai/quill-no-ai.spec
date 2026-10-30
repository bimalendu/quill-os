Name:           quill-no-ai
Version:        44
Release:        1%{?dist}
Summary:        Quill OS policy: no built-in AI features enabled by default
License:        MIT
URL:            https://quill-os.example/
BuildArch:      noarch

Source1:        policies.json
Source2:        ai-denylist.txt

BuildRequires:  python3

# Firefox reads policies from <install dir>/distribution/policies.json only.
# The file is added next to Firefox; this package does not require it.
Supplements:    firefox

%description
Turns off the AI features that ship inside other software. For Firefox 149.0.2
and later this is the AIControls policy: every Firefox AI feature (sidebar
chatbot, link preview summaries, smart tab groups, translations, PDF alt text,
smart windows, speech recognition) is blocked by default, and the setting is not
locked, so users can switch features on in Firefox's own settings.

Also installs the list of packages Quill OS will not ship (ai-denylist.txt) for
reference. That list is enforced when images are built, not on this system.


%prep


%build


%install
install -Dpm 0644 %{SOURCE1} %{buildroot}/usr/lib64/firefox/distribution/policies.json
install -Dpm 0644 %{SOURCE2} %{buildroot}%{_datadir}/quill/ai-denylist.txt


%check
python3 - <<'PY'
import json
p = json.load(open("%{SOURCE1}"))["policies"]["AIControls"]
assert p["Default"]["Value"] == "blocked", "AI features must be blocked by default"
assert p["Default"]["Locked"] is False, "policy is deliberately not locked"
PY


%files
%dir /usr/lib64/firefox
%dir /usr/lib64/firefox/distribution
%config(noreplace) /usr/lib64/firefox/distribution/policies.json
%dir %{_datadir}/quill
%{_datadir}/quill/ai-denylist.txt


%changelog
* Fri Oct 30 2026 Quill OS Maintainers <maintainers@quill-os.example> - 44-1
- Initial Quill OS no-AI policy package

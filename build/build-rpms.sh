#!/bin/sh
# Build every packages/*/*.spec, sign the RPMs with the dev key and publish
# them as an rpm-md repository. Runs inside the builder container.
#
#   /src    packages/ tree (read-only copy)
#   /keys   GPG home for the dev signing key (created on first run)
#   /repo   output rpm-md repository
set -eu

export GNUPGHOME=/keys/gnupg
KEYNAME="Quill OS dev signing key <dev@quill-os.example>"

mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
# Dev key only: no passphrase, so no pinentry is needed to create or use it.
if ! gpg --list-secret-keys "$KEYNAME" >/dev/null 2>&1; then
    gpg --batch --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "$KEYNAME" rsa4096 sign never
    echo "created dev signing key"
fi
mkdir -p /repo
gpg --export --armor "$KEYNAME" > /repo/RPM-GPG-KEY-quill-dev

top=$(mktemp -d)
for spec in /src/*/*.spec; do
    dir=$(dirname "$spec")
    echo ">>> building $(basename "$spec")"
    rpmbuild -ba "$spec" \
        --define "_topdir $top" \
        --define "_sourcedir $dir" \
        --define "_gpg_name $KEYNAME" \
        >"$top/build.log" 2>&1 || { tail -40 "$top/build.log"; exit 1; }
done

find "$top/RPMS" "$top/SRPMS" -name '*.rpm' | while read -r rpm; do
    rpmsign --addsign --define "_gpg_name $KEYNAME" "$rpm" >/dev/null
done

rm -rf /repo/rpms /repo/srpms
mkdir -p /repo/rpms /repo/srpms
find "$top/RPMS" -name '*.rpm' -exec cp {} /repo/rpms/ \;
find "$top/SRPMS" -name '*.rpm' -exec cp {} /repo/srpms/ \;
createrepo_c --quiet --general-compress-type gz /repo
rpm --import /repo/RPM-GPG-KEY-quill-dev
echo "published:"; ls /repo/rpms

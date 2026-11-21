#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

version=$(<VERSION)
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid VERSION'; exit 1; }
asset="Archaive-$version-arm64.dmg"
[[ -f "dist/$asset" ]] || { print -u2 "Build dist/$asset before signing."; exit 1; }
(cd dist && shasum -a 256 -c "$asset.sha256")

sparkle_version=2.10.1
tools_dir="$PWD/.build/sparkle-tools/$sparkle_version"
archive="$tools_dir/Sparkle-$sparkle_version.tar.xz"
if [[ ! -x "$tools_dir/bin/sign_update" || ! -x "$tools_dir/bin/generate_keys" ]]; then
    mkdir -p "$tools_dir"
    if [[ ! -f "$archive" ]]; then
        curl --fail --silent --show-error --location \
            "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" \
            --output "$archive"
    fi
    digest=$(shasum -a 256 "$archive")
    [[ "${digest%% *}" == 1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27 ]] || {
        print -u2 'Sparkle tools archive does not match its pinned checksum.'
        exit 1
    }
    tar -xf "$archive" -C "$tools_dir" ./bin
fi

account=roxvi.arachive
[[ "$("$tools_dir/bin/generate_keys" --account "$account" -p)" == "$(<updates/public-key)" ]] || {
    print -u2 'The Keychain account does not match the update key embedded in Archaive.'
    exit 1
}

signature=$("$tools_dir/bin/sign_update" --account "$account" -p "dist/$asset")
length=$(stat -f %z "dist/$asset")
feed_dir=$(mktemp -d "$PWD/dist/.update-feed.XXXXXX")
trap 'if [[ -f "$feed_dir/appcast.xml" ]]; then unlink "$feed_dir/appcast.xml"; fi; rmdir "$feed_dir"' EXIT
cat > "$feed_dir/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Archaive Updates</title>
    <link>https://github.com/roxvi/arachive/releases</link>
    <description>Stable releases of Archaive for Apple Silicon</description>
    <item>
      <title>Archaive $version</title>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/roxvi/arachive/releases/download/v$version/$asset"
                 length="$length" type="application/octet-stream" sparkle:edSignature="$signature" />
    </item>
  </channel>
</rss>
XML
"$tools_dir/bin/sign_update" --account "$account" "$feed_dir/appcast.xml"
mv "$feed_dir/appcast.xml" dist/appcast.xml
print 'Signed dist/appcast.xml. Publish the DMG and checksum before copying the feed to updates/appcast.xml.'

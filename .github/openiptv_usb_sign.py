import base64
import hashlib
import json
import os
import plistlib
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives.serialization import NoEncryption, load_pem_private_key, pkcs12

BUNDLE_ID = "tech.hopecash.openiptv"
IPA_HASH = "fa968ba0592c8c9f7b9e707e8302129d77860ca24bf7d087d714da8b5fb17d34"

temp = Path(os.environ["RUNNER_TEMP"])
work = temp / "openiptv-usb"
work.mkdir()
udid = os.environ["OPENIPTV_USB_DEVICE_UDID"]
assert udid, "Identificador do iPhone não configurado"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def apple(*args):
    result = run("app-store-connect", *args, "--json", "--log-stream", "stderr", stdout=subprocess.PIPE)
    data = json.loads(result.stdout)
    return data.get("data", data) if isinstance(data, dict) else data


def attribute(resource, name):
    return resource.get("attributes", resource).get(name)


def normalize_udid(value):
    return (value or "").replace("-", "").upper()


unsigned = work / "unsigned.ipa"
run("openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-iter", "200000", "-in",
    ".github/openiptv-usb.ipa.enc", "-out", str(unsigned), "-pass", "env:OPENIPTV_USB_IPA_PASSWORD")
assert hashlib.sha256(unsigned.read_bytes()).hexdigest() == IPA_HASH, "IPA original não confere"
run("ditto", "-x", "-k", str(unsigned), str(work))
app = work / "Payload/App.app"
assert plistlib.loads((app / "Info.plist").read_bytes())["CFBundleIdentifier"] == BUNDLE_ID

devices = apple("devices", "list", "--platform", "IOS")
device = next((item for item in devices if normalize_udid(attribute(item, "udid")) == normalize_udid(udid)), None)
if device is None:
    registered = apple("devices", "register", "--name", "iPhone OpenIPTV", "--udid", "@env:OPENIPTV_USB_DEVICE_UDID")
    device = registered[0] if isinstance(registered, list) else registered
assert attribute(device, "status") == "ENABLED", "Dispositivo desabilitado na equipe Apple Developer"
print("Dispositivo registrado e habilitado", flush=True)

bundles = apple("bundle-ids", "list", "--bundle-id-identifier", BUNDLE_ID, "--strict-match-identifier")
bundle = bundles[0] if bundles else apple("bundle-ids", "create", BUNDLE_ID, "--name", "OpenIPTV")

key = load_pem_private_key(os.environ["IOS_CERTIFICATE_PRIVATE_KEY"].encode(), password=None)
certificates = apple("certificates", "list", "--type", "DISTRIBUTION", "--type", "IOS_DISTRIBUTION")
for resource in certificates:
    candidate = x509.load_der_x509_certificate(base64.b64decode(attribute(resource, "certificateContent")))
    if candidate.public_key() == key.public_key() and candidate.not_valid_after_utc > datetime.now(timezone.utc):
        break
else:
    resource = apple("certificates", "create", "--type", "DISTRIBUTION",
                     "--certificate-key", "@env:IOS_CERTIFICATE_PRIVATE_KEY")
    candidate = x509.load_der_x509_certificate(base64.b64decode(attribute(resource, "certificateContent")))
cert_id = resource["id"]
cert_der = base64.b64decode(attribute(resource, "certificateContent"))
identity = hashlib.sha1(cert_der).hexdigest().upper()
p12 = work / "signing.p12"
p12.write_bytes(pkcs12.serialize_key_and_certificates(b"OpenIPTV", key, candidate, None, NoEncryption()))

profile_name = f"OpenIPTV USB {hashlib.sha256((device['id'] + cert_id).encode()).hexdigest()[:10]}"
profiles = apple("profiles", "list", "--type", "IOS_APP_ADHOC", "--state", "ACTIVE", "--name", profile_name)
profile = profiles[0] if profiles else apple("profiles", "create", bundle["id"], "--type", "IOS_APP_ADHOC", "--name",
                                            profile_name, "--certificate-ids", cert_id, "--device-ids", device["id"])
if not attribute(profile, "profileContent"):
    profile = apple("profiles", "get", profile["id"])
embedded = app / "embedded.mobileprovision"
embedded.write_bytes(base64.b64decode(attribute(profile, "profileContent")))
settings = plistlib.loads(run("security", "cms", "-D", "-i", str(embedded), stdout=subprocess.PIPE).stdout)
assert {normalize_udid(d) for d in settings["ProvisionedDevices"]} == {normalize_udid(udid)}, "Perfil tem outro dispositivo"
assert cert_der in settings["DeveloperCertificates"], "Certificado diferente do provisionamento"
profile_entitlements = settings["Entitlements"]
assert profile_entitlements["application-identifier"].split(".", 1)[1] == BUNDLE_ID
entitlements = work / "entitlements.plist"
entitlements.write_bytes(plistlib.dumps({
    name: profile_entitlements[name]
    for name in ("application-identifier", "com.apple.developer.team-identifier", "get-task-allow")
    if name in profile_entitlements
}))

run("keychain", "initialize")
run("keychain", "add-certificates", "--certificate", str(p12))
for framework in (app / "Frameworks").glob("*.framework"):
    run("codesign", "--force", "--sign", identity, "--timestamp=none", str(framework))
run("codesign", "--force", "--sign", identity, "--timestamp=none", "--generate-entitlement-der",
    "--entitlements", str(entitlements), str(app))
run("codesign", "--verify", "--deep", "--strict", str(app))
run("ditto", "-c", "-k", "--keepParent", str(work / "Payload"), str(temp / "OpenIPTV-iPhone-USB.ipa"))

import base64
import hashlib
import json
import os
import plistlib
import secrets
import subprocess
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives.hashes import SHA1
from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, PublicFormat, load_pem_private_key, pkcs12

BUNDLE_ID = "tech.hopecash.openiptv"
IPA_HASH = "272b91b39391c9768411c1b0ad9b82f4223c5e4c5a9a2cb0bb063e1af0379f98"

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
run("curl", "--fail", "--silent", "--show-error", "--retry", "2", "--max-time", "30",
    "--output", str(unsigned), "https://iptv.hopecash.tech/openiptv-ios.ipa")
assert hashlib.sha256(unsigned.read_bytes()).hexdigest() == IPA_HASH, "IPA original não confere"
run("ditto", "-x", "-k", str(unsigned), str(work))
app = work / "Payload/App.app"
info = plistlib.loads((app / "Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == BUNDLE_ID
assert info["NSAppTransportSecurity"] == {"NSAllowsArbitraryLoads": True}

profile = apple("profiles", "get", "U3JL7LX53X")
embedded = app / "embedded.mobileprovision"
embedded.write_bytes(base64.b64decode(attribute(profile, "profileContent")))
settings = plistlib.loads(run("security", "cms", "-D", "-i", str(embedded), stdout=subprocess.PIPE).stdout)
assert {normalize_udid(d) for d in settings["ProvisionedDevices"]} == {normalize_udid(udid)}, "Perfil tem outro dispositivo"

key = load_pem_private_key(os.environ["IOS_CERTIFICATE_PRIVATE_KEY"].encode(), password=None)
public_key = key.public_key().public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo)
for cert_der in settings["DeveloperCertificates"]:
    candidate = x509.load_der_x509_certificate(cert_der)
    if candidate.public_key().public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo) == public_key:
        break
else:
    raise RuntimeError("O certificado do perfil não corresponde à chave existente da equipe")

identity = hashlib.sha1(cert_der).hexdigest().upper()
p12 = work / "signing.p12"
p12_password = secrets.token_hex(24)
print(f"::add-mask::{p12_password}", flush=True)
os.environ["OPENIPTV_USB_P12_PASSWORD"] = p12_password
p12_encryption = (
    PrivateFormat.PKCS12.encryption_builder()
    .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
    .hmac_hash(SHA1())
    .build(p12_password.encode())
)
p12.write_bytes(pkcs12.serialize_key_and_certificates(b"OpenIPTV", key, candidate, None, p12_encryption))
profile_entitlements = settings["Entitlements"]
assert profile_entitlements["application-identifier"].split(".", 1)[1] == BUNDLE_ID
entitlements = work / "entitlements.plist"
entitlements.write_bytes(plistlib.dumps({
    name: profile_entitlements[name]
    for name in ("application-identifier", "com.apple.developer.team-identifier", "get-task-allow")
    if name in profile_entitlements
}))

run("keychain", "initialize")
run("keychain", "add-certificates", "--certificate", str(p12), "--certificate-password", "@env:OPENIPTV_USB_P12_PASSWORD")
for framework in (app / "Frameworks").glob("*.framework"):
    run("codesign", "--force", "--sign", identity, "--timestamp=none", str(framework))
run("codesign", "--force", "--sign", identity, "--timestamp=none", "--generate-entitlement-der",
    "--entitlements", str(entitlements), str(app))
run("codesign", "--verify", "--deep", "--strict", str(app))
run("ditto", "-c", "-k", "--keepParent", str(work / "Payload"), str(temp / "OpenIPTV-iPhone-USB.ipa"))

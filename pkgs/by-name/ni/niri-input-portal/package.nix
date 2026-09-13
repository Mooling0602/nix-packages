{
  fetchFromGitHub,
  lib,
  libxkbcommon,
  pkg-config,
  rustPlatform,
  wayland,
}:

let
  # Upstream publishes no tags and no releases, so the revision is pinned by
  # commit; see update.sh, which moves both to the current main HEAD.
  rev = "f363e34380b3f8bd9ffc9a167b7b58d3c208574b";
  version = "unstable-2026-07-26";
in
rustPlatform.buildRustPackage {
  pname = "niri-input-portal";
  inherit version;

  src = fetchFromGitHub {
    owner = "Qingswe";
    repo = "niri-input-portal";
    inherit rev;
    hash = "sha256-teX8coQ7sHqSiQSSnt+IOJj6eta+YD/q+DuXqEfWxoU=";
  };

  # Upstream never reports an `ei_device.region`, the only thing a libei client
  # has to size "this screen" with. Deskflow therefore keeps its 1x1 fallback,
  # maps every activation onto (0, 0) and can only ever release the pointer
  # towards the top edge — a client placed below or to the right of this machine
  # is unreachable. See the patch header for the full trace.
  patches = [ ./fix-eis-device-region.patch ];

  # Vendored crate hash; update.sh recomputes it whenever the revision moves.
  cargoHash = "sha256-UD9jSOyY+p7JbgvfzI1zcRisITFvjGoKWscvqzylldg=";

  # Upstream ships no tests.
  doCheck = false;

  nativeBuildInputs = [ pkg-config ];

  # libxkbcommon is a real runtime dependency: it lands in DT_NEEDED and in the
  # RUNPATH. wayland is only needed so smithay-client-toolkit's build script
  # can find it through pkg-config — the binary itself uses wayland-backend's
  # pure Rust client and never loads libwayland at runtime.
  buildInputs = [
    libxkbcommon
    wayland
  ];

  postPatch = ''
    # Upstream's install.sh writes these to a /usr prefix. Point them at the
    # store path instead; the D-Bus service file keeps its
    # SystemdService=niri-input-portal.service reference, which the unit has
    # to match.
    for template in \
      data/org.freedesktop.impl.portal.desktop.niri-input.service \
      data/niri-input-portal.service
    do
      substituteInPlace "$template" \
        --replace-fail "/usr/lib/niri-input-portal" "${placeholder "out"}/bin/niri-input-portal"
    done
  '';

  postInstall = ''
    install -Dm644 data/niri-input.portal \
      "$out/share/xdg-desktop-portal/portals/niri-input.portal"
    install -Dm644 data/org.freedesktop.impl.portal.desktop.niri-input.service \
      "$out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.niri-input.service"

    # nixpkgs' moveSystemdUserUnits hook relocates this to share/systemd/user,
    # which is on the systemd user search path once the package is in a
    # profile. It still cannot activate on its own — D-Bus starts it — but it
    # carries ConditionEnvironment=WAYLAND_DISPLAY, so read README.md before
    # relying on it instead of declaring the unit.
    install -Dm644 data/niri-input-portal.service \
      "$out/lib/systemd/user/niri-input-portal.service"
  '';

  meta = {
    description = "xdg-desktop-portal InputCapture backend for the niri compositor";
    longDescription = ''
      Implements org.freedesktop.impl.portal.InputCapture on top of Wayland
      protocols niri supports, so KVM software that speaks the input-capture
      portal (Synergy 3, Deskflow, Input Leap) can share this machine's
      keyboard, mouse and clipboard with another computer.
    '';
    homepage = "https://github.com/Qingswe/niri-input-portal";
    license = lib.licenses.mit;
    mainProgram = "niri-input-portal";
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}

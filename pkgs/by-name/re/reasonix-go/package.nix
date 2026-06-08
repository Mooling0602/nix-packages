{ lib
, buildGoModule
, fetchFromGitHub
, versionCheckHook
}:

buildGoModule rec {
  pname = "reasonix-go";
  version = "unstable-2026-06-01";

  src = fetchFromGitHub {
    owner = "esengine";
    repo = "deepseek-reasonix";
    rev = "8e00ae5205bc0bc1683228a2182a6a31069caf40";
    hash = "sha256-0tGyq1AzI5g+o4I+/k723BnSKlDONUCM2zfiMTGoeRk=";
  };

  vendorHash = "sha256-x8hiH2IGW7e1g+CcTMWjtbCeO8b3f8nzsF6LTVu7R1A=";

  subPackages = [
    "cmd/reasonix"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  meta = {
    description = "DeepSeek-native AI coding agent with TUI, MCP, and Wails desktop support";
    homepage = "https://github.com/esengine/deepseek-reasonix";
    license = lib.licenses.mit;
    mainProgram = "reasonix";
    platforms = lib.platforms.unix;
  };
}

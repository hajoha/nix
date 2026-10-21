{
  lib,
  pkgs,
  ...
}:
{
  services.ollama = {
    enable = true;

    # CPU-only host (Xeon E3-1275 v5, no GPU). The default `pkgs.ollama`
    # builds the CPU runtime unless nixpkgs has cuda/rocm support enabled
    # globally — pin it so a stray cudaSupport flag can't pull a GPU build.
    package = pkgs.ollama;

    # Listen on all interfaces so nix-sure (10.60.1.37) can reach it.
    # Access is still gated by the per-node firewall in your nodes file.
    host = "0.0.0.0";
    port = 11434;

    # Preload the model declaratively so it's ready after a rebuild.
    # llama3.1:8b has solid native tool-calling, which Sure's AI assistant
    # depends on. Alternatives: "qwen3:8b" (also strong tools),
    # "llama3.2:3b" (faster, weaker at tools), "gemma2:9b".
    loadModels = [ "llama3.1:8b" ];

    environmentVariables = {
      # Force the CPU library (belt-and-suspenders alongside the package).
      OLLAMA_LLM_LIBRARY = "cpu";
      # Keep the model resident so background categorization doesn't pay a
      # cold disk-load each run. Holds ~5 GB RAM; drop to "5m" or "0" to free it.
      OLLAMA_KEEP_ALIVE = "30m";
      # Single CPU inference at a time — avoids thrashing 8 threads.
      OLLAMA_NUM_PARALLEL = "1";
    };

    # Firewall is handled in the nodes file (nix-ollama), matching your
    # convention. If you'd rather the module own it, set this true and drop
    # 11434 from the node's allowedTCPPorts:
    # openFirewall = true;
  };

  # --- LXC / systemd-hardening escape hatch --------------------------------
  # The upstream ollama unit ships aggressive sandboxing (PrivateUsers,
  # MemoryDenyWriteExecute, ProtectKernelModules, capability bounding...).
  # In an *unprivileged* Proxmox LXC some of these can stop the service from
  # starting. If `systemctl status ollama` shows a namespace/permission error,
  # ensure the container has `features: nesting=1`, then uncomment:
  #
  # systemd.services.ollama.serviceConfig = {
  #   PrivateUsers            = lib.mkForce false;
  #   MemoryDenyWriteExecute  = lib.mkForce false;
  #   ProtectKernelModules    = lib.mkForce false;
  #   ProtectKernelTunables   = lib.mkForce false;
  #   RestrictNamespaces      = lib.mkForce false;
  #   NoNewPrivileges         = lib.mkForce false;
  # };
}

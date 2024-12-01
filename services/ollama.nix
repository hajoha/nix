{ pkgs, inputs, ... }:
{
    services.ollama = {
        enable = true;
        acceleration = "rocm";
        environmentVariables = {
            HCC_AMDGPU_TARGET = "amdgcn-amd-amdhsa--gfx1103"; # used to be necessary, but doesn't seem to anymore
        };
#        rocmOverrideGfx = "10.3.1";
#        loadModels = [ "llama3.1:8b" ];
    };

}

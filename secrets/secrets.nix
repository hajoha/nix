let
  k1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIocRHpz5SimboTEV6r/YGafvLqNO5qH//VdzcInV/CB";
  k2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOqJ5bYFU3ge9YitVPBe0nCphGNzRk7JrIf59XCNM0cr";
  k3 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIINQi5Dlk3UEpkbi0lJOe0EsEnbxW5Mdhe2kf/yX/uy+";
  keys = [ k1 k2 k3 ];
in
{
  "secret.age".publicKeys = keys;
}

# age keys that are not containers (those live in nodes.nix as `age`).
{
  # Can decrypt every secret in the repo.
  admins = {
    fokus = "age1cag8j93g8jjw860fwecrcl4qvvmk7k9e00puehxacy6dl55ye5eqsg7h7a";
    private = "age1vm9pqxhup6gkekltk4j8k6kzxzpz5kugmtytzmc8vcphd70t73ssycmm4t";
  };

  hosts = {
    homelab = "age1pcd76fcxy8d2t43f7d9eck6gg0upq59vtz4lzw0f4jvpmwmauu0qd48xwj";
    hetzner-vps-01 = "age1vdphsnzygqqr233crr2v9gdh0wvktclnz0hrddhtgmzddy0tpplssvrc2r";
    pi3-sendspin = "age150pdxatszqnp2xcgymmlgyqv3lw67epuz4vv8ptsqf5js227w5jq6g4nhs";
  };
}

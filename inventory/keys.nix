# age keys that are not LXC nodes (those live in nodes.nix as `age`).
{
  # Can decrypt every secret in the repo.
  admins = {
    fokus = "age1cag8j93g8jjw860fwecrcl4qvvmk7k9e00puehxacy6dl55ye5eqsg7h7a";
    private = "age1vm9pqxhup6gkekltk4j8k6kzxzpz5kugmtytzmc8vcphd70t73ssycmm4t";
  };

  hosts = {
    pve2 = "age1tsmms30cyluwl707nmkqaxp6qwmdsmxsf928l0mpnmauhay7nqes3f722s";
    hetzner-vps-01 = "age1vdphsnzygqqr233crr2v9gdh0wvktclnz0hrddhtgmzddy0tpplssvrc2r";
    pi3-sendspin = "age150pdxatszqnp2xcgymmlgyqv3lw67epuz4vv8ptsqf5js227w5jq6g4nhs";
  };
}

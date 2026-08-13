{ lib }:

{
  parseSize =
    value:
    let
      match = builtins.match "([0-9]+)([KMGTPE]?)" (lib.toUpper value);
      amount = builtins.fromJSON (builtins.elemAt match 0);
      suffix = builtins.elemAt match 1;
      factors = {
        "" = 1;
        K = 1024;
        M = 1048576;
        G = 1073741824;
        T = 1099511627776;
        P = 1125899906842624;
        E = 1152921504606846976;
      };
    in
    amount * factors.${suffix};
}

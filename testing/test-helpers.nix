{ pkgs }:
let
  inherit (pkgs) lib;
in
rec {
  verify-test-case = name: definition: {
    inherit name;
    value = (import ./test-harness.nix {
      testname = name;
      starting-spare-dbs = definition.starting-spare-dbs;
      test-script = pkgs.writeScript "phases.${name}" ''
        #!${pkgs.bash}/bin/bash

        set -eux

        ${lib.concatMapStrings (p: "${p}\n") definition.test-phases}
      '';
    });
  };

  phase = name: script: let
    test = pkgs.writeScript "test.${name}" ''
      #!${pkgs.bash}/bin/bash
      set -eux
      ${script}
    '';

  in pkgs.writeScript "test.${name}.wrapper" ''
    #!${pkgs.bash}/bin/bash
    systemd-cat -t "${name}" ${test}
    RET=$?
    if [ $RET -eq 0 ]; then
      echo " OK: ${name}" | systemd-cat -t "test.${name}.wrapper"
    else
      echo " FAIL: ${name} (exit code: $RET)"  | systemd-cat -t "test.${name}.wrapper"
    fi
    exit $RET
  '';

  expect-phase = name: script: let
    test = pkgs.writeScript "test.${name}.expect" ''
      #!${pkgs.expect}/bin/expect -f

      ${script}
    '';
  in phase name ''
    export PAGER=cat

    ${test}
  '';

  jetpants-phase = name: code: (phase name (pkgs.jetpants.ruby_script name code));

  assert-shard-exists = name: jetpants-phase "assert-shard-exists-${name}" ''
    abort if Jetpants.pool('${name}').nil?
  '';

  assert-shard-does-not-exist = name: jetpants-phase "assert-shard-does-not-exist-${name}" ''
    abort unless Jetpants.pool('${name}').nil?
  '';

  assert-master-has-n-slaves = shard: slaves: jetpants-phase "assert-${shard}-has-${toString slaves}-slaves" ''
    abort "Actual: #{Jetpants.pool('${shard}').slaves.length}" unless Jetpants.pool('${shard}').slaves.length == ${toString slaves}
  '';
}
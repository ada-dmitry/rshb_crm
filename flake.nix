{
  description = "CRM возврата покупателей — окружение разработки";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Версия MRI Ruby берётся из .ruby-version.
    nixpkgs-ruby.url = "github:bobvanderlinden/nixpkgs-ruby";
    nixpkgs-ruby.inputs.nixpkgs.follows = "nixpkgs";

    # Форматирование кода (rubocop, nixfmt) единой командой `nix fmt`.
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    # git pre-commit хук: при входе в `nix develop` ставит хук, который
    # перед каждым коммитом гоняет treefmt (см. ниже) и блокирует коммит,
    # если тот что-то поправил.
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-ruby,
      treefmt-nix,
      git-hooks,
    }:
    let
      system = "x86_64-linux";

      pkgs = nixpkgs.legacyPackages.${system};

      ruby = nixpkgs-ruby.lib.packageFromRubyVersionFile {
        file = ./.ruby-version;
        inherit system;
      };

      # nix fmt использует RuboCop проекта и nixfmt.
      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.rubocop.enable = true;
        # Use the project's locked gems and Ruby, not nixpkgs' Ruby 3.4 RuboCop.
        programs.rubocop.package = pkgs.writeShellScriptBin "rubocop" ''
          export BUNDLE_PATH="''${BUNDLE_PATH:-vendor/bundle}"
          exec ${ruby}/bin/ruby bin/rubocop "$@"
        '';
        programs.nixfmt.enable = true;
      };

      # Устанавливается shellHook'ом ниже при входе в devShell. Требует
      # git-репозиторий (`git init`) — вне git просто ничего не делает.
      preCommitCheck = git-hooks.lib.${system}.run {
        src = ./.;
        hooks.treefmt = {
          enable = true;
          package = treefmtEval.config.build.wrapper;
        };
      };

      # PostgreSQL runs only on request; direnv loads the environment but
      # does not own long-lived processes.
      dbUp = pkgs.writeShellApplication {
        name = "db-up";
        runtimeInputs = [
          pkgs.postgresql_16
          pkgs.coreutils
        ];
        text = ''
          : "''${PGHOST:?Enter the project with direnv first}"
          : "''${PGDATA:?Enter the project with direnv first}"
          mkdir -p "$PGHOST"
          chmod 700 "$PGHOST"
          if [ ! -d "$PGDATA" ]; then
            initdb -D "$PGDATA" -U "$USER" --encoding=UTF8 --locale=C
          fi
          if pg_ctl -D "$PGDATA" status >/dev/null 2>&1; then
            echo "PostgreSQL уже запущен"
          else
            pg_ctl -D "$PGDATA" -l "$(dirname "$PGDATA")/pg.log" -o "-k $PGHOST -c listen_addresses=" start
          fi
        '';
      };
      dbDown = pkgs.writeShellApplication {
        name = "db-down";
        runtimeInputs = [ pkgs.postgresql_16 ];
        text = ''
          : "''${PGDATA:?Enter the project with direnv first}"
          if [ ! -d "$PGDATA" ] || ! pg_ctl -D "$PGDATA" status >/dev/null 2>&1; then
            echo "PostgreSQL уже остановлен"
          else
            pg_ctl -D "$PGDATA" stop -m fast
          fi
        '';
      };
    in
    {
      formatter.${system} = treefmtEval.config.build.wrapper;

      # `nix flake check` проверит, что хуки/форматтер валидны и что
      # дерево уже отформатировано (best-effort).
      checks.${system}.pre-commit-check = preCommitCheck;

      devShells.${system}.default = pkgs.mkShell {
        # Компилятор для native-расширений gems.
        nativeBuildInputs = with pkgs; [
          pkg-config
          stdenv.cc
          gnumake
        ];

        buildInputs = with pkgs; [
          ruby

          nodejs_22
          yarn

          postgresql_16
          libpq # системная либа для gem `pg`

          dbUp
          dbDown

          redis

          libxml2 # nokogiri
          libxslt # nokogiri
          zlib # nokogiri и многие другие gems
          openssl
          libyaml
          libffi
          foreman

          git
        ];

        # Bundler не должен пытаться писать gems в read-only Nix store —
        # ставим их в проектную папку.
        BUNDLE_PATH = "vendor/bundle";

        # `pg` берёт libpq из Nix через pkg-config, а не случайный
        # pg_config из PATH или системный /usr/lib.
        BUNDLE_BUILD__PG = "--with-pg-config=ignore";

        # Nokogiri использует libxml2/libxslt/zlib из Nix-окружения вместо
        # сборки своих копий из исходников.
        BUNDLE_BUILD__NOKOGIRI = "--use-system-libraries";

        shellHook = ''
          ${preCommitCheck.shellHook}

          export PATH="$PWD/bin:$PATH"

          # direnv загружает пути, но не запускает сервер. Из корня проекта:
          # db-up (инициализация при первом вызове и запуск), db-down (остановка).
          export PGDATA="$PWD/tmp/pgdata"
          export PGHOST="$PWD/tmp/pgsocket"

          echo "Ruby:    $(ruby --version)"
          echo "Bundler: $(bundle --version)"
          echo "Node:    $(node --version)"
          echo "Yarn:    $(yarn --version)"
          echo "psql:    $(psql --version)"
        '';
      };
    };
}

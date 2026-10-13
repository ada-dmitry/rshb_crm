{
  # ЗАМЕНИТЕ на описание своего проекта.
  description = "Ruby/Rails dev shell template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Даёт точные MRI Ruby-версии (включая свежие вроде 3.3.0 / 4.0.5),
    # которых часто ещё нет в основном nixpkgs. Версия берётся из файла
    # .ruby-version в корне проекта.
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
      # ── ПЛАТФОРМА ────────────────────────────────────────────────
      # Один system вместо flake-utils/forAllSystems — проще читать,
      # но шаблон соберётся только под неё. Если нужен ещё
      # aarch64-darwin (Mac) или aarch64-linux — смотри пример с
      # forAllSystems в DZR/nto_2026/flake.nix и адаптируй по образцу.
      system = "x86_64-linux";

      pkgs = nixpkgs.legacyPackages.${system};

      # Требует файл .ruby-version в корне проекта (стандартно для
      # rbenv/rvm/bundler). ЗАМЕНИТЕ версию в .ruby-version на нужную вам —
      # шаблон несёт плейсхолдер "3.3.0" только чтобы `nix develop` сразу
      # работал после `nix flake init -t`.
      ruby = nixpkgs-ruby.lib.packageFromRubyVersionFile {
        file = ./.ruby-version;
        inherit system;
      };

      # ── ФОРМАТТЕР ────────────────────────────────────────────────────
      # `rubocop` форматирует/автофиксит Ruby-код (`.rubocop.yml` в корне
      # проекта, если есть, подхватится сам). `nixfmt` заодно форматирует
      # сам flake.nix. Запуск: `nix fmt`. Другие форматтеры — из
      # https://github.com/numtide/treefmt-nix/tree/main/programs.
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

      # ── PRE-COMMIT ХУК ────────────────────────────────────────────────
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
        # ── СБОРКА NATIVE-РАСШИРЕНИЙ ─────────────────────────────────
        # Нужны для `bundle install`, когда какие-то gems (nokogiri,
        # ffi и т.п.) компилируют C-код при установке. Оставьте как есть.
        nativeBuildInputs = with pkgs; [
          pkg-config
          stdenv.cc
          gnumake
        ];

        buildInputs = with pkgs; [
          # Ruby-версия берётся из .ruby-version, см. выше.
          # Bundler идёт вместе с Ruby как default gem — отдельно не нужен.
          ruby

          # ── ОПЦИОНАЛЬНО: frontend-тулчейн ───────────────────────────
          # Уберите этот блок (+ вызовы node/yarn ниже в shellHook), если
          # в проекте нет JS/asset pipeline (например чистый API-only
          # Rails или Sinatra-проект без фронта).
          nodejs_22
          yarn

          # ── ОПЦИОНАЛЬНО: PostgreSQL ──────────────────────────────────
          # Уберите postgresql_16 и libpq, если БД не Postgres или её
          # вообще нет в проекте. Заодно уберите BUNDLE_BUILD__PG ниже
          # и команды db-up/db-down ниже.
          postgresql_16
          libpq # системная либа для gem `pg`

          dbUp
          dbDown

          # ── ОПЦИОНАЛЬНО: Redis ────────────────────────────────────────
          # Нужен для Sidekiq / ActionCable / кэша через gem `redis`
          # (пригодится, например, для attendance_mephi-подобных проектов).
          # Уберите, если Redis в проекте не используется.
          redis

          # ── Зависимости часто встречающихся native gems ────────────
          # Можно оставить как есть почти для любого Rails-проекта —
          # эти либы дешёвые и почти всегда пригождаются.
          libxml2 # nokogiri
          libxslt # nokogiri
          zlib # nokogiri и многие другие gems
          openssl
          libyaml
          libffi
          foreman # запуск Procfile.dev (`bin/dev`) — уберите, если не используете

          git
        ];

        # Bundler не должен пытаться писать gems в read-only Nix store —
        # ставим их в проектную папку. Обычно не трогать.
        BUNDLE_PATH = "vendor/bundle";

        # ── ОПЦИОНАЛЬНО: см. блок PostgreSQL выше — убрать вместе с ним ──
        # `pg` берёт libpq из Nix через pkg-config, а не случайный
        # pg_config из PATH или системный /usr/lib.
        BUNDLE_BUILD__PG = "--with-pg-config=ignore";

        # Nokogiri использует libxml2/libxslt/zlib из Nix-окружения вместо
        # сборки своих копий из исходников (иначе `bundle install` может
        # идти по нескольку минут). Обычно оставлять как есть.
        BUNDLE_BUILD__NOKOGIRI = "--use-system-libraries";

        shellHook = ''
          ${preCommitCheck.shellHook}

          export PATH="$PWD/bin:$PATH"

          # ── ОПЦИОНАЛЬНО: сокет локального PostgreSQL ──────────────────
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

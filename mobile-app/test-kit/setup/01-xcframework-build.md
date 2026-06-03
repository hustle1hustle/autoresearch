# 01 — Build TLSN Prover as `.xcframework`

**Когда нужно.** Item ⑧ в PLAN.md. подмена `MockProver` на реальный TLSN прувер.

**Что получишь.** `tlsn-build/ios/TlsnProver.xcframework` который ты dragу в Xcode project, и `import TlsnProver` работает.

**Время.** ~1-2 часа first time, ~10 минут на rebuild после изменений.

**Prerequisites.**
- macOS с Xcode 15+ (для `xcodebuild -create-xcframework`)
- Rust toolchain. `rustup` installed
- iOS Rust targets. `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`
- UniFFI bindgen. `cargo install uniffi-bindgen` или поднимется автоматически как cargo dep

---

## Откуда мы извлекаем

Текущий location TLSN мобильного прувера. **`tlsnotary/tlsn-extension` → `app/mobile/modules/tlsn-mobile/`** (Expo native module).

Структура:
```
app/mobile/modules/tlsn-mobile/
├── ios/                    ← Expo wrapper (нам не нужен)
├── android/                ← Android wrapper (нам не нужен)
├── src/                    ← Rust source. ЭТО ЯДРО
│   ├── lib.rs              ← UniFFI exports (initialize, prove, proveUntilReveal, ...)
│   ├── prover.rs           ← Prover wrapper around tlsn-core
│   └── ...
└── Cargo.toml              ← Rust deps
```

Нам нужно build именно `src/` как standalone xcframework, без Expo wrapper'а.

## Steps

### 1. Clone и подготовь

```bash
cd ~/dev  # или где у тебя workspace
git clone https://github.com/tlsnotary/tlsn-extension.git
cd tlsn-extension/app/mobile/modules/tlsn-mobile
```

### 2. Add iOS Rust targets если ещё нет

```bash
rustup target add aarch64-apple-ios       # реальный iPhone
rustup target add aarch64-apple-ios-sim   # симулятор на M1/M2/M3 Mac
rustup target add x86_64-apple-ios        # симулятор на Intel Mac (legacy)
```

### 3. Update Cargo.toml для standalone build

Добавь / убедись что есть:

```toml
[lib]
name = "tlsn_prover"
crate-type = ["staticlib", "cdylib"]

[features]
default = []
ffi = ["uniffi"]

[dependencies]
uniffi = { version = "0.27", features = ["cli"] }
# ... остальные TLSN deps уже там
```

### 4. Build static libs для всех iOS targets

```bash
cargo build --release --target aarch64-apple-ios --features ffi
cargo build --release --target aarch64-apple-ios-sim --features ffi
# опционально для Intel sim:
# cargo build --release --target x86_64-apple-ios --features ffi
```

Output. `target/<target-triple>/release/libtlsn_prover.a`

### 5. Generate Swift bindings через UniFFI

```bash
cargo run --bin uniffi-bindgen generate src/lib.udl --language swift --out-dir ./generated
```

Output:
- `generated/TlsnProver.swift` — Swift API surface
- `generated/TlsnProverFFI.h` — C header
- `generated/TlsnProverFFI.modulemap` — module map

Если `lib.udl` не существует, проверь что в Cargo.toml `default = ["ffi"]` и `uniffi_macros` подключен. Тогда bindings генерятся из `#[uniffi::export]` attributes напрямую.

### 6. Lipo для sim universal (опционально)

Если хочешь один static lib который работает и на arm64 sim и на x86_64 sim:

```bash
mkdir -p target/sim-universal/release
lipo -create \
  target/aarch64-apple-ios-sim/release/libtlsn_prover.a \
  target/x86_64-apple-ios/release/libtlsn_prover.a \
  -output target/sim-universal/release/libtlsn_prover.a
```

Если только M1/M2/M3 Mac — skip, используй `aarch64-apple-ios-sim` напрямую.

### 7. Pack как `.xcframework`

```bash
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libtlsn_prover.a \
  -headers generated/ \
  -library target/aarch64-apple-ios-sim/release/libtlsn_prover.a \
  -headers generated/ \
  -output TlsnProver.xcframework
```

Output. `TlsnProver.xcframework/` с правильной структурой для Xcode.

### 8. Скопируй в наш test-kit

```bash
mkdir -p /path/to/autoresearch/mobile-app/test-kit/tlsn-build/ios
cp -R TlsnProver.xcframework /path/to/autoresearch/mobile-app/test-kit/tlsn-build/ios/
cp generated/TlsnProver.swift /path/to/autoresearch/mobile-app/test-kit/tlsn-build/ios/
```

### 9. Wire в Xcode project

В `Package.swift` или Xcode project:

```swift
.binaryTarget(
    name: "TlsnProver",
    path: "../test-kit/tlsn-build/ios/TlsnProver.xcframework"
),
```

Или через Xcode UI. drag `TlsnProver.xcframework` в `Frameworks, Libraries, and Embedded Content`. Set "Embed & Sign".

И добавь `TlsnProver.swift` в target.

### 10. Verify import работает

В любом Swift файле:
```swift
import TlsnProver

let prover = try TlsnProver.initialize()
print("Prover initialized: \(prover)")
```

Если компилируется без errors — done.

---

## Build script (для CI / rebuilds)

Сохрани как `tlsn-build/build-xcframework.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

TLSN_DIR="${1:-$HOME/dev/tlsn-extension/app/mobile/modules/tlsn-mobile}"
OUT_DIR="${2:-$(dirname "$0")/ios}"

cd "$TLSN_DIR"

echo "Building Rust libs..."
cargo build --release --target aarch64-apple-ios --features ffi
cargo build --release --target aarch64-apple-ios-sim --features ffi

echo "Generating Swift bindings..."
cargo run --bin uniffi-bindgen generate src/lib.udl --language swift --out-dir ./generated

echo "Creating xcframework..."
rm -rf "$OUT_DIR/TlsnProver.xcframework"
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libtlsn_prover.a \
  -headers generated/ \
  -library target/aarch64-apple-ios-sim/release/libtlsn_prover.a \
  -headers generated/ \
  -output "$OUT_DIR/TlsnProver.xcframework"

cp generated/TlsnProver.swift "$OUT_DIR/"

echo "Done. xcframework at $OUT_DIR/TlsnProver.xcframework"
```

Make executable. `chmod +x tlsn-build/build-xcframework.sh`

Run. `./tlsn-build/build-xcframework.sh ~/dev/tlsn-extension/app/mobile/modules/tlsn-mobile`

---

## Common pitfalls

### "module 'TlsnProverFFI' not found"

В Xcode project Build Settings добавь:
- `MODULEMAP_FILE` → `$(SRCROOT)/../test-kit/tlsn-build/ios/TlsnProver.xcframework/<arch>/TlsnProver.framework/Modules/module.modulemap`

Or регенерь bindings — может modulemap battle damaged.

### "Undefined symbol: _tlsn_prover_..."

Static lib не линкуется. Проверь:
1. xcframework правильно добавлен в "Frameworks, Libraries, and Embedded Content" с Embed & Sign
2. `OTHER_LDFLAGS` содержит `-ObjC` если используешь Objective-C calls

### "Code signing error"

Free Apple ID OK для simulator, но real device может потребовать paid Developer account. Альтернатива. unsigned build для personal device development через xattr workaround (не рекомендую для production).

### Build занимает 10+ минут

Normal first time. Rust release mode + iOS targets = heavy. Subsequent builds incremental, ~30 секунд если только src/ изменился.

### "Target architecture mismatch"

На M1/M2/M3 Mac симулятор требует `aarch64-apple-ios-sim`, не `x86_64-apple-ios`. Проверь Xcode сборку Build Settings → "Excluded Architectures" → DEBUG → Any iOS Simulator SDK → пусто (или удали `arm64` если был).

---

## Verify build готов

```bash
ls -la mobile-app/test-kit/tlsn-build/ios/
# должно содержать:
# TlsnProver.xcframework/
# TlsnProver.swift
```

И в Swift коде должно работать:
```swift
import TlsnProver

@MainActor
class TLSNProver: TLSNProving {
    let inner = try TlsnProver.initialize()

    func prove(...) async throws -> Proof {
        // call inner.prove(...)
    }
}
```

→ Готов к item ⑧ в PLAN.md (mock → real swap).

## Что обновить в kit после успешной сборки

1. `test-kit/open-questions.md` → Q1 RESOLVED with measured prover capabilities
2. `test-kit/open-questions.md` → Q2 RESOLVED (no separate connect API per coding agent earlier)
3. `test-kit/comparison/template.csv` → можешь начать заполнять реальные cells

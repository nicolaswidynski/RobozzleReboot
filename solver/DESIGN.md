# Robozzle Solver — Tasarım Spesifikasyonu (v1.1)

> **Dil / Language:** Türkçe metin aşağıda. The English version follows the
> Turkish one: [jump to English](#english). Both versions describe the same
> spec with the same section numbers and rule IDs; if they ever disagree, fix
> both in the same change.

Bu belge solver'ın **ne yapacağını ve neden doğru olduğunu** anlatır:
kuralların gerekçelerini, ispatlarını ve değerlendirilen alternatifleri.
**Normatif sözleşme [`SPEC.md`](SPEC.md)'dir** (İngilizce): tip ve fonksiyon
isimleri, kesin geçiş kuralları, test vektörleri ve çıktı formatı oradadır.
İki belge çelişirse SPEC.md geçerlidir ve ikisi aynı değişiklikte düzeltilir.
Bu belgedeki isimler (`Level`, `Cond::Is` gibi) açıklama amaçlıdır; kodda
SPEC.md'deki isimler kullanılır.

> **v1.2 — ölçümden doğan eklemeler.** İlk katalog ölçümü iki şeyi gösterdi.
> (1) Arama süresinin neredeyse tamamı, stack'i durmadan büyüten kuyruk
> olmayan özyinelemeyi 20 000 adım boyunca çalıştırmaya gidiyordu; bu tür
> bir çalışma hiçbir state'i birebir tekrarlamadığı için döngü tespiti onu
> yakalayamıyordu. **C-PUMP** (SPEC §12): aynı fiziksel durum ve aynı çalışan
> frame tekrar görüldüğünde, önceki caller zincirinin tepe düğümü hâlâ
> zincirdeyse aradaki çalışma sonsuza kadar tekrar eder. Hız ~1 200 kat arttı.
> (2) `Any:X` ile `<mevcut renk>:X` bir slota yazıldığı anda aynı davranır;
> farkları ancak slot başka renkte çalışınca ortaya çıkar. **D-PENDING /
> D-CHOOSE** (SPEC §13) bu kararı `CondOnly` gibi gözlemlenebilir olana kadar
> erteler; aktif aday sayısı yarıya iner. Yanında iki ucuz kural: **P-CRASH**
> (hemen boşluğa çıkacak `Forward` üretilmez) ve **P-ENDDEAD** (askıda frame
> yokken `END` programı bitirir). Hepsi `Config` ile kapatılabilir ve
> sonuçları [`BENCHMARKS.md`](BENCHMARKS.md)'de.
>
> **v1.3 — sezgisel aşama.** Kesin arama her ek slotta işi ~10 katına
> çıkardığı için 10–11 slotun ötesine geçemiyor; oysa zor bulmacaların
> çözümleri daha uzun. Stockfish'in gücü "iyi hamleyi önce dene" ilkesinden
> gelir; burada aynı ilkeyi **en kısa garantisini bozmadan** ekliyoruz
> (SPEC §17). Önce kesin arama node bütçesinin yarısını kullanır; çözüm
> yoksa aynı ağaçta *Limited Discrepancy Search* çalışır: her karar
> noktasında çocuklar bir kez çalıştırılıp toplanan yıldıza ve en yakın
> yıldıza uzaklığa göre sıralanır; arama önce en iyi yolu, sonra ondan
> sapmaları dener. Bulunan çözüm doğrulanır, gereksiz hücreleri silinerek
> kısaltılır ve kalan bütçeyle daha kısası aranır. Sonuç `optimal: true`
> (kanıtlı en kısa) ya da `optimal: false` + `lowerBound` olarak raporlanır.
> Rastgelelik yok, bütçe node sayısı: sonuç her makinede aynı.
>
> Hata analizi iki şey daha gösterdi: kesin ve sezgisel arama arasındaki
> bütçe paylaşımı bir takas (ölçülen marjinal değere göre oran 1:1), ve
> başarısız aramalar çoğu zaman yıldızların %90'ından fazlasını toplayıp
> sonra ölen programlara ulaşıp onları unutuyor. **History heuristic**
> (satranç motorlarındaki gibi) her kararın altında görülen en iyi ilerlemeyi,
> ölü dallar dahil, hatırlar ve o kararları önce dener. Sadece sıralamayı
> değiştirir; 444 → 461.
>
> **v1.4 — çatışmadan öğrenme neden yok, yerine ne var.** SAT çözücülerdeki
> gibi nogood öğrenme + geri sıçrama önerisi muhalif bir incelemeyle
> ölçüldü: tembel sentezde her karar verilen hücre hatadan önce çalışır ve
> RoboZZle'da çalışan her komut robotun pozunu ya da kontrol akışını
> etkiler. 1,82 milyon ölü yaprakta sağlam sebep kümesi yolun %98,7–99,6'sı
> çıktı; boyasız bulmacalarda %100. Geri sıçrama kronolojik geri dönüşe
> dönüşüyor (%0,1–1,8 kazanç). Onun yerine aynı ilkenin ("gözlemlenene kadar
> karar verme", "en kısa çözümde olamayacak şeyi üretme") yeni örnekleri
> eklendi: **anonim yardımcı fonksiyonlar** (kapasite sınıfları arasındaki
> isim simetrisi, INV-FIT eşleştirmesiyle), **D-DEFER-SET** (ertelenen
> rengin kendisi de ertelenir), **P-SINGLE** (yardımcı fonksiyon tek hücreli
> olamaz) ve **P-RESERVE** (çağrılan her yardımcı fonksiyona en az 2 slot
> ayrılır: ilk kanıtlı alt sınır).
>
> **v1.5 — ölçüm disiplini.** Ürün modu tek bir node bütçesini kesin ve
> sezgisel arama arasında paylaştırır; bir değişiklik birini iyileştirip
> diğerini kötüleştirebilir ve toplam neredeyse kıpırdamaz. Bu yüzden her
> değişiklik hedeflediği benchmark'ta ölçülür: **EXACT** (`--exact-only`:
> kanıtlanan optimumlar ve alt sınırlar), **FINDER** (`--heuristic-only`:
> bulunan çözümler) ve **PRODUCT** (varsayılan mod: kullanıcının aldığı).
> Geliştirme 150 bulmacalık sabit bir dev set üzerinde 5 M node ile yapılır;
> tam katalog yalnızca bir değişikliği doğrulamak için koşulur.
>
> **v1.6 — azalan history ve yerel onarım.** Dev set'teki telemetri iki şey
> gösterdi. (1) History heuristic'in düz maksimumu, bir kez uzağa gidip sonra
> hep hayal kırıklığı yaratan bir kararı sonsuza kadar öne çeker. **Azalan
> history** (SPEC §17.3): alt ağaç girdiyi geçerse girdi hemen yükselir
> (bonus), geçemezse ona doğru dörtte bir iner (malus). Stockfish tarzı
> "gravity" tabloları, önceki karara ya da robotun durumuna göre anahtarlanan
> bağlamsal tablolar ve farklı azalma hızları da ölçüldü; en basiti kazandı
> (BENCHMARKS.md). (2) LDS çoğu zaman bir çözüme bir-iki hücre uzaklıkta
> ölen programlara ulaşır, ama o çözüme ancak çok daha fazla sapmayla
> varabilir. **Yerel onarım** (SPEC §17.5) en iyi programların düzenleme
> komşuluğunu doğrudan arar: bir hücreyi değiştirmek, silmek ya da araya
> eklemek, ve iki düzenleme. Her aday, ortak önek yeniden çalıştırılmadan,
> ilk farklılaştığı noktadan simüle edilir. Onarım node harcar ama hiçbir
> şeyi budamaz ve sıralamayı değiştirmez; bulduğu her program sezgisel
> çözümler gibi referans yorumlayıcıda doğrulanır. Dev set'te (5 M node)
> FINDER 26 → 40, PRODUCT 20 → 29; tam katalogda (20 M node) çözülen
> bulmaca 478 → 521, kanıtlı en kısa 393 → 399, 4 fonksiyonlu bulmacalar
> 18 → 34.

Kimlik etiketleri (`R-*`, `N-*`, `S-*`, `INV-*`, `P-*`, `T-*`) koddaki
yorumlarda ve test isimlerinde referans olarak kullanılır. Örneğin bir budama
kuralının kodu `// P-TURN` yorumu taşır, testi `t_p_turn_*` diye adlandırılır.

---

## 0. Amaç ve temel ilkeler

**Amaç:** `assets/levels_catalog.json` içindeki (ve editörde yapılmış) her
bulmaca için, uygulamanın motorunda
([`lib/engine/interpreter.dart`](../lib/engine/interpreter.dart)) başarıyla
çalışan ve **dolu slot sayısı en az olan** programı bulmak.

- **Birincil hedef:** dolu (non-empty) slot sayısını en aza indirmek.
- **Kısıt:** gerçek motordaki 20000 adım sınırı. Bu bir hedef değil, bir kısıttır.
- **İkincil hedef (v1'de yok):** aynı slot sayısında daha az adım.

Dört ilke her kararın üstündedir:

1. **Motor semantiği kutsaldır.** Solver'ın "çözüm" dediği her program Dart
   motorunda `RunStatus.success` vermek ZORUNDADIR (§2, §10).
2. **Budama yalnızca kanıtla yapılır.** Bir dal ancak içinde en küçük bir
   çözüm olamayacağı *ispatlanabiliyorsa* kesilir. "Kötü görünüyor" bir budama
   sebebi değildir; sezgisel (heuristic) bilgi yalnızca dalların *sırasını*
   belirler (§8.6).
3. **Belirlenimcilik.** Aynı girdi her zaman aynı çıktıyı verir. Arama
   kararları hiçbir zaman `HashMap` iterasyon sırasına bağlı olmaz.
4. **Ölçülebilirlik.** Her optimizasyon bir `Config` bayrağıyla kapatılabilir
   ve etkisi `SearchStats` ile ölçülür (§8.7, §9.4). Bir optimizasyonu kapatmak
   hiçbir zaman çözüm kaybettirmez, sadece aramayı büyütür.

---

## 1. Terimler

| Terim | Anlamı |
|---|---|
| Fonksiyon `F1..F5` | Koddaki indeksleri `0..4`. `F1` programın giriş noktası. |
| Kapasite `cap[f]` | Bulmacanın o fonksiyona verdiği slot sayısı (`slotsPerFunction`). `0` ise fonksiyon yok. |
| Fiziksel program | Her fonksiyon için `cap[f]` uzunluğunda, her elemanı `null` ya da komut olan dizi. Dart'taki `RobotProgram`. |
| Kısmi program | Aramanın o ana kadar karar verdiği program (§4.2). |
| Adım (step) | Motorun `stepsExecuted` sayacı. Her **boş olmayan** slot değerlendirmesinde +1 (§2). |
| Frontier | Çalıştırmanın, programda henüz karar verilmemiş bir noktaya gelip durduğu an. |
| Maliyet | Programdaki dolu slot sayısı. |
| Çalışan frame | Şu an komutları yürütülen frame (`current`). |
| Askıdaki frame | Bir çağrı yapıp dönüşü bekleyen frame (`callers` zincirinde). |

---

## 2. Referans semantik (motor sözleşmesi)

Aşağıdaki algoritma `interpreter.dart`'ın **birebir** özetidir. Parantez içindeki
sayılar o dosyadaki satır numaralarıdır (commit `37b5ede`). Motor değişirse bu
bölüm ve `reference.rs` birlikte güncellenir.

```text
REFERENCE_RUN(level, program):                                 # R-RUN
    pos, dir   = level.start
    colors     = level'ın başlangıç renkleri
    stars      = level'daki yıldızlar
    steps      = 0
    stack      = [(F1, 0)]  if cap[F1] > 0 else []             (112)
    if stars.is_empty(): return SUCCESS                        (111)

    loop:
        if stack.is_empty():                                   (185)
            return SUCCESS if stars.is_empty() else OUT_OF_INSTRUCTIONS
        (f, i) = stack.top
        if i >= cap[f]:  stack.pop(); continue                 (193)   # R-POP
        slot = program[f][i];  stack.top.i += 1
        if slot == null: continue                              (202)   # R-NULL
        steps += 1                                             (206)   # R-STEP
        if steps > MAX_STEPS: return STUCK                     (207)
        if slot.cond != Any and colors[pos] != slot.cond:      (221)   # R-COND
            continue
        match slot.action:
            Call(g):
                if cap[g] == 0: continue                       (232)
                if program[f][stack.top.i ..] hepsi null:      (240)   # R-TAIL
                    stack.pop()
                stack.push((g, 0))
            TurnLeft:  dir = (dir + 3) % 4
            TurnRight: dir = (dir + 1) % 4
            Paint(c):  colors[pos] = c
            Forward:                                           (271)
                n = neighbor(pos, dir)
                if n yok (grid dışı ya da boşluk): return CRASHED  (279)
                pos = n
                if stars.contains(n): stars.remove(n)
                if stars.is_empty(): return SUCCESS            (288)
```

`MAX_STEPS = 20000` (93). Uygulamadaki her ekran varsayılan değeri kullanıyor.

Kritik noktalar (her birinin testi var, §11):

- **R-STEP:** Adım sınırı kontrolü, koşul kontrolünden **ve** komutun
  çalışmasından **önce** yapılır. 20001. dolu slot hiçbir etki yaratmaz: robot
  hareket etmez, yıldız alınmaz. Koşulu tutmayan komutlar da, `cap = 0` olan
  fonksiyona yapılan çağrılar da adım sayar. `null` slotlar ve fonksiyondan
  dönüşler adım saymaz.
- **R-TAIL:** Çağıranın kalan slotlarının hepsi `null` ise çağıranın frame'i
  push'tan önce silinir. Bunun gözlemlenebilir tek etkisi stack'in
  derinliğidir; davranışı değiştirmez, çünkü silinmeseydi de o frame dönüşte
  adım saymadan pop olurdu.
- Stack derinliğinin sınırı yoktur. Solver da bir sınır **koymaz**. (Pratikte
  derinlik adım sayısıyla, yani 20000 ile sınırlıdır.)
- Yıldız yalnızca bir kareye **girerken** alınır. Katalogda başlangıç karesinde
  yıldız olan bulmaca yok; olsaydı bile, o yıldız robot o kareye tekrar
  girmeden alınmış sayılmazdı.

---

## 3. Girdi ve ön işleme

### 3.1 Girdi ve desteklenen sınırlar

Her kayıt: `sourceId`, `rows` (string listesi), `startRow`, `startCol`,
`startDirection` (`up|right|down|left`), `slotsPerFunction` (5 sayı),
`allowedCommands` (boya bitmask'ı: `1` = kırmızı, `2` = yeşil, `4` = mavi).

Karakterler: `' '` ya da `'.'` boşluk; `r g b` renkli kare; `R G B` aynı
renkte, üzerinde yıldız olan kare.

Solver'ın sınırları, hem katalogu hem de uygulamanın editörünü
([`editor_screen.dart:44-45`](../lib/screens/editor/editor_screen.dart))
kapsayacak şekilde seçildi:

| Sabit | Değer | Katalogda görülen | Editörün izin verdiği |
|---|---|---|---|
| `MAX_TILES` (`rows × cols`) | 256 | 192 (12×16) | 196 (14×14) |
| `MAX_FUNCTION_SLOTS` | 12 | 10 | 12 |

**Doğrulama:** Loader her bulmacayı yüklerken şunları kontrol eder: bütün
satırlar aynı uzunlukta; başlangıç karesi grid içinde ve boşluk değil;
`cap[F1] > 0`; bilinmeyen karakter yok; yukarıdaki sınırlar aşılmıyor. Bir
kontrol başarısız olursa o bulmaca için `Unsupported(sebep)` döner.
**Hiçbir zaman sessizce kırpılmaz ve panic olmaz**; diğer bulmacalar
çözülmeye devam eder.

Yıldızı olmayan bir bulmaca (editörde mümkün) geçerlidir: boş program onu
çözer (§9.1).

### 3.2 Hazırlanan statik veri (`Level`)

| Alan | Tanım |
|---|---|
| `TileId` | `row * cols + col`, `u8` (≤ 255). Boşluklar da bir `TileId` alır ama `is_tile = false`. |
| `neighbor[tile][dir]` | `Option<TileId>`. Grid dışı ya da boşluk ise `None`. |
| `init_colors` | Başlangıç renkleri, `PackedColors` (§4.3). |
| `init_stars` | Yıldızlı karelerin kümesi, `StarSet = [u64; 4]` bitset. |
| `allowed_paints` | `allowedCommands` bitmask'ından türetilen renk kümesi. |
| `possible_colors` | `{başlangıçta griddeki renkler} ∪ allowed_paints` (§8.2). |
| `cap[0..5]` | Fonksiyon kapasiteleri. |
| `classes` | F2..F5 için kapasite sınıfları (§8.4). |

Yön kodlaması: `Up = 0, Right = 1, Down = 2, Left = 3`.
`turn_left(d) = (d + 3) % 4`, `turn_right(d) = (d + 1) % 4`.

### 3.3 Statik kontroller

- **P-CONN:** Başlangıç karesinden BFS ile gidilebilen karelerin dışında
  yıldız varsa bulmaca `Unsolvable(Disconnected)` döner ve arama hiç başlamaz.
  Grid'in şekli boyamayla değişmediği için bu kontrol bir kez yapılır.

---

## 4. Veri yapıları

### 4.0 Mimari: paylaşılan bağlam ve dal state'i

İki tür veri var ve karıştırılmamaları gerekiyor:

```rust
// Bütün arama boyunca bir tane. Dallarla kopyalanmaz.
struct Solver {
    level: Level,          // statik bulmaca (§3.2)
    config: Config,        // ablation bayrakları (§8.7)
    limits: Limits,        // zaman ve node sınırı
    arena: StackArena,     // askıdaki frame'ler (§6)
    stats: SearchStats,    // sayaçlar (§9.4)
}

// Bir dalın tüm anlamsal durumu. Copy; her çocuk dal için kopyalanır.
#[derive(Clone, Copy)]
struct SearchState {
    program: PartialProgram,
    machine: Machine,
    used: u8,          // maliyet: Resolved + CondOnly hücre sayısı
    introduced: u8,    // bitmask: çağrı hücresi oluşturulmuş fonksiyonlar (§8.4)
}
```

**Kopyala ve ilerle (copy-make).** Bir çocuk dal açmak, `SearchState`'i
kopyalamak demektir (heap'siz, birkaç yüz bayt). Undo/trail kaydı tutulmaz.
Tek istisna arena'dır: o `mark()` / `truncate(mark)` ile geri sarılır (§6.1).

*Neden undo değil:* Satranç motorlarında bir hamle birkaç kareyi değiştirir
ve hemen yeni bir node'a geçilir. Bizde her node'da `normalize()` binlerce
adım çalıştırabilir. Trail yaklaşımı her boyamayı ve her yıldız toplamayı
bu en sıcak döngüde kaydetmek zorunda kalır. Kopyalama ise bedeli node
başına bir kez öder. `SearchStats` kopyalamanın bir darboğaz olduğunu
gösterirse bu karar yeniden değerlendirilir (§15).

`Config` ve `SearchStats` hiçbir zaman `SearchState` içinde olmaz. Olsalardı
her kopyada sayaçlar da kopyalanır ve anlamlarını yitirirdi.

### 4.1 Komutlar

```rust
enum Color { Red, Green, Blue }
enum Cond  { Any, Is(Color) }
enum Action { Forward, TurnLeft, TurnRight, Paint(Color), Call(FnId) }
```

### 4.2 Kısmi program

```rust
#[derive(Clone, Copy)]
enum Cell {
    Resolved { cond: Cond, action: Action },
    CondOnly { cond: Color },          // koşul seçildi, aksiyon henüz yok
}

#[derive(Clone, Copy)]
struct FunctionDraft {
    cells: [Cell; MAX_FUNCTION_SLOTS], // yalnızca cells[..len] anlamlı
    len: u8,                           // karar verilmiş hücre sayısı (soldan sıkıştırılmış)
    ended: bool,                       // true: len'den sonrası kesin olarak boş (END)
}

#[derive(Clone, Copy)]
struct PartialProgram { fns: [FunctionDraft; 5] }
```

Temsilde `UNKNOWN` ve `EMPTY` diye bir hücre **yoktur**:
`len < cap && !ended` ise bir sonraki slot henüz karar verilmemiştir;
`ended` ise o noktadan sonrası boştur.

Tanımlar:

- **Kapalı fonksiyon:** `closed(f) := fns[f].ended || fns[f].len == cap[f]`.
- **Tükenmiş frame:** `exhausted(f, pc) := pc == fns[f].len && closed(f)`. Bu
  frame'in önünde kesin olarak çalışacak hiçbir komut yoktur.
- Fiziksel karşılık: `physical(f) = cells[..len] (hepsi Resolved) ++ [null; cap[f] - len]`.

**Lemma L1 (sola sıkıştırma).** Bir fonksiyondaki `null` slotları sona taşımak
davranışı değiştirmez. `null` adım saymaz ve atlanır (R-NULL). R-TAIL yalnızca
"sonrasında dolu slot var mı?" sorusuna bakar ve bunun cevabı taşımayla
değişmez. Fonksiyonlara yalnızca başlarından girilir, slot indeksine atlayan
bir komut yoktur. Dolayısıyla her fiziksel programın aynı davranışa ve aynı
maliyete sahip tek bir sola sıkıştırılmış hali vardır, ve yalnızca bu halleri
aramak hiçbir çözümü kaybettirmez.

### 4.3 Makine

```rust
#[derive(Clone, Copy)]
struct Machine {
    pos: TileId,
    dir: u8,
    colors: PackedColors,       // kare başına 2 bit → 64 bayt
    stars: StarSet,             // [u64; 4] → 32 bayt
    star_count: u16,
    steps: u32,
    current: Option<Frame>,     // çalışan frame; pc'si her komutta ilerler
    callers: Option<NodeId>,    // askıdaki frame'ler, arena'daki kalıcı zincir (§6)
    phys_hash: u128,            // pos, dir, stars, colors'ın Zobrist hash'i (§7.3)
}

#[derive(Clone, Copy)]
struct Frame { f: u8, pc: u8 }
```

Stack **kopyalanmaz**: `Machine` sadece `current` frame'i ve `callers`
zincirinin tepesini gösteren bir `NodeId` tutar. Zincirin kendisi arena'da
değişmez olarak durur.

---

## 5. `normalize()`: çalıştırma katmanı

`normalize(solver, state, cycles) -> Outcome`, kısmi program altında makineyi
**yerinde** ilerletir. **Programı değiştirmez ve hiçbir karar vermez.** Sentez
(program oluşturma) yalnızca arama katmanının işidir (§9); bu sınır
bozulmamalıdır.

```rust
enum Outcome {
    Solved,
    Dead(DeadReason),                   // Crash | StepLimit | OutOfInstructions | Loop
    OpenSlot   { f: u8, pc: u8 },       // pc == len(f), fonksiyon kapalı değil
    NeedAction { f: u8, pc: u8, cond: Color },
}
```

```text
normalize(P, M, cycles):                                        # N-*
    loop:
        if M.star_count == 0: return Solved                     # N-SOLVED
        if M.current is None: return Dead(OutOfInstructions)
        (f, pc) = M.current

        if pc == len(f):                                        # N-END
            if closed(f): pop(M); continue                      # R-POP ile aynı
            return OpenSlot{f, pc}                              # ADIM SAYILMAZ, pc İLERLEMEZ

        match P.fns[f].cells[pc]:

            CondOnly{c}:                                        # N-CONDONLY
                if M.colors[M.pos] == c:
                    return NeedAction{f, pc, c}                 # ADIM SAYILMAZ, pc İLERLEMEZ
                consume_step(M)?                                # sınır aşıldı → Dead(StepLimit)
                M.current.pc += 1
                continue                                        # koşul tutmadı, atla

            Resolved{cond, action}:                             # N-RESOLVED
                consume_step(M)?                                # R-STEP: ÖNCE sınır
                M.current.pc += 1
                if cond == Is(c) and M.colors[M.pos] != c: continue
                match action:
                    Forward:
                        n = neighbor[M.pos][M.dir]
                        if n is None: return Dead(Crash)
                        move(M, n)                              # yıldız varsa al, hash güncelle
                    TurnLeft / TurnRight: turn(M)
                    Paint(c): paint(M, c)
                    Call(g):
                        call(P, M, g)                           # §6.2, R-TAIL dahil
                        if config.cycle_detection and cycles.observe(M) == Repeated:
                            return Dead(Loop)                   # §7

consume_step(M) -> Result<(), DeadReason>:                      # tek adım sayacı
    M.steps += 1
    if M.steps > MAX_STEPS: Err(StepLimit) else Ok(())
```

**`consume_step` adım sayacına dokunan tek fonksiyondur.** Kodun başka hiçbir
yerinde `steps += 1` yazılmaz.

Hücreler hiçbir zaman `cap[g] == 0` olan bir fonksiyonu çağırmaz (§8.3), bu
yüzden R-RUN'daki (232) dalının karşılığına gerek yoktur.

**Lemma L2 (frontier'da durmak).** `OpenSlot` ve `NeedAction` durumunda makine,
o slot değerlendirilmeden **hemen önceki** state'tedir: adım sayılmamış, `pc`
ilerlememiştir. Karar verildikten sonra `normalize` aynı slotu motorun yaptığı
gibi baştan işler. Böylece her dolu slot tam olarak bir kez sayılır. Koşulu
tutmayan bir `CondOnly` ise aksiyona ihtiyaç duymadığı için hemen sayılır ve
atlanır.

**Lemma L3 (frontier'dan devam).** Frontier'a kadar olan çalışma, karar
verilecek hücreyi hiç okumamıştır; okusaydı orada dururdu. Bu yüzden her çocuk
dal, frontier makinesinin bir kopyasından devam edebilir. Baştan çalıştırmaya
gerek yoktur.

**Lemma L4 (eşdeğerlik).** Bir programın bütün hücreleri `Resolved` ise ve
`normalize` hiç frontier'a varmadan `Solved`, `Crash`, `StepLimit` ya da
`OutOfInstructions` ile bitiyorsa, `REFERENCE_RUN(physical(P))` aynı sonucu,
aynı `steps` değerini ve aynı son state'i verir. `Loop` sonucunda ise
referans çalıştırma ya `STUCK` verir ya da hiç sonlanmaz. Bu lemma T-DIFF
testiyle doğrulanır.

---

## 6. Stack

### 6.1 Temsil ve arena

Çalışan frame (`M.current`) `Machine` içinde durur ve onun `pc`'si her komutta
ilerler; bunun için arena'ya dokunulmaz. Askıdaki frame'lerin `pc`'si ise
**askıdayken değişmez**, bu yüzden arena içinde kalıcı (persistent) bir bağlı
liste olarak tutulurlar:

```rust
struct StackNode {
    frame: Frame,
    parent: Option<NodeId>,
    depth: u16,      // zincirdeki frame sayısı (≤ 20000)
    hash: u128,      // mix(parent.hash (yoksa 0), frame.f, frame.pc)
}
type NodeId = u32;   // StackArena içindeki indeks

stack_hash(M) = mix(hash(M.callers), M.current.f, M.current.pc)     # O(1)
```

- **Arena:** `Vec<StackNode>`. Düğümler hiçbir zaman değiştirilmez.
- **Geri sarma:** Arama derinlik öncelikli (DFS) olduğu için yer açma da
  yığın disipliniyle yapılır. Her çocuk dal için `mark = arena.mark()` **aday
  uygulanmadan önce** alınır (çünkü END onarımı da düğüm oluşturur), dal
  bitince `arena.truncate(mark)` çağrılır. Ebeveyn state'in gösterdiği düğümler
  mark'tan önce oluşturulduğu için etkilenmez.
- Bir cache kaydı stack'i kopyalamaz, sadece bir `NodeId` tutar. Böylece derin
  özyinelemede bile kayıt başına O(1) bellek harcanır.

### 6.2 İşlemler

```text
call(P, M, g):                                                   # S-CALL
    # M.current.pc zaten çağrı komutunun bir sonrasını gösteriyor
    if exhausted(M.current.f, M.current.pc):   # R-TAIL: çağıranın devamı kesin boş
        M.current = (g, 0)                     # replace, arena'ya dokunulmaz
    else:
        M.callers = arena.push(M.current, parent = M.callers)   # askıya al
        M.current = (g, 0)

pop(M):                                                          # S-POP
    if M.callers is None: M.current = None
    else:
        node = arena[M.callers]
        M.current = node.frame
        M.callers = node.parent
```

Üçü de O(1). Devamı henüz karar verilmemiş bir slot içeren çağıran (fonksiyon
kapalı değil) askıya alınır; o slot ileride bir komut olabilir.

**Motordan fark ve eşdeğerlik.** Motor R-TAIL'de "kalan fiziksel slotların
hepsi `null` mı?" diye sorar. Biz `exhausted(...)` diye soruyoruz. Çağıranın
kalanında bir `UNKNOWN` varsa frame'i tutarız; motor ise o slot sonradan
`null` olursa frame'i silerdi. Bu fark davranışı değiştirmez (R-TAIL notu),
sadece stack'in gösterimini değiştirir. Gösterimi düzeltmek için §6.3'teki
kural uygulanır.

### 6.3 Canonical stack (INV-STACK)

**INV-STACK:** Askıdaki frame'lerin hiçbiri `exhausted` değildir. Çalışan
frame tükenmiş olabilir; o zaman döngünün başında pop edilir.

**Lemma L5.** Tek bir `normalize` çağrısı boyunca INV-STACK korunur. Bir frame
ancak tükenmemişse askıya alınır (S-CALL), ve bir frame'in tükenmiş olup
olmadığı sadece programa bağlıdır. `normalize` programı değiştirmediği için
askıdaki bir frame sonradan tükenmiş hale gelemez.

**Lemma L6.** Karar türleri arasında INV-STACK'i yalnızca **END** bozabilir:

| Karar | Askıdaki frame'lere etkisi |
|---|---|
| `Resolved` ya da `CondOnly` eklemek (`len` +1) | Devamı `UNKNOWN` olan frame'lere bir komut ekler. Kapasite dolduysa bile, askıdaki frame'lerin `pc ≤ eski len`, orada artık bir komut var. Tükenmiş frame yaratmaz. |
| `NeedAction` çözmek | Hücre zaten vardı. Etkisi yok. |
| **END (`f`, `k`)** | `(f, pc == k)` olan askıdaki frame'ler tükenmiş hale gelir. |

**S-REBUILD:** END kararı `OpenSlot{f, k}` frontier'ında verilir. Bu an
**çalışan frame'in kendisi** `(f, k)`'dir; END'e o frame'in slotu için karar
verilir. Kararın ardından, **yalnızca o çocuk dalın** state kopyası üzerinde:

```text
frames = M.callers zincirini alttan üste topla
frames = [fr for fr in frames if !(fr.f == f and fr.pc == k)]
M.callers = frames'i arenaya sırayla yeniden push et   # parent, depth, hash yeniden hesaplanır
```

Çalışan `(f, k)` frame'i onarıma dahil değildir: normalize döngüsünün başında
tükenmiş olarak pop edilir. Maliyet O(derinlik), ama çağrı başına değil END
kararı başına ödenir.

**Ulaşılabilir örnek** (`t_rebuild_middle`): `B` fonksiyonu, `C` üzerinden
kendini çağırmış olsun. Stack alttan üste:

```text
B@k (askıda),  C@j (askıda),  B@k (çalışan, OpenSlot{B, k})
```

`B[k] = END` kararından sonra çalışan `B@k` pop olur, `C@j` çalışan frame olur,
alttaki `B@k` onarımla silinir. Sonuç: `[C@j (çalışan)]`.

---

## 7. Döngü tespiti

### 7.1 Kural

Bir `Call` gerçekleştikten sonra (S-CALL bittikten sonra) makinenin **döngü
anahtarı** hesaplanır:

```text
key(M) = (pos, dir, stars, colors, callers zinciri, current)     # steps DAHİL DEĞİL
```

Anahtar daha önce görüldüyse sonuç `Dead(Loop)` olur.

**Neden sadece Call'da?** Çağrı içermeyen her çalıştırma parçası sonludur:
fonksiyonlar sonlu uzunlukta ve slot indeksine atlama yok. Sonsuz bir
çalıştırma sonsuz sayıda çağrı içermek zorundadır, dolayısıyla tekrar eden bir
state bir çağrı noktasında da tekrar eder.

**Lemma L7 (doğruluk).** Aynı program altında `S → … → S` gözlendiyse,
çalıştırma belirlenimci olduğu için bu yol sonsuza kadar tekrar eder. Her
tekrar adım harcar, yıldız sayısı değişmez (yıldız sayısı anahtarın parçası),
dolayısıyla bu dal hiçbir zaman `Solved` olamaz.

### 7.2 Cache'in ömrü

`CycleDetector` **her `normalize` çağrısında sıfırdan oluşturulur**: v1'de
her sentez kararından sonra yeni bir cache açılır.

*Gerekçe (kodda aynen yazılacak):* Aynı DFS ata zinciri üzerinde, yol
kapsamlı bir döngü cache'i sentez kararlarından sonra da güvenle yaşayabilir.
Program hücreleri yalnızca eklenerek rafine edilir (monoton), ve tamamlanmış
tekrar eden bir çalıştırma yolu yalnızca o ata zinciri boyunca zaten sabitlenmiş
hücrelere bağlıdır. v1, uygulama sadeliği için döngü tespitini her
normalize çağrısında bilerek sıfırlar; bedeli döngünün en fazla bir tur geç
yakalanmasıdır. **Cache kayıtları hiçbir zaman kardeş dallar arasında
paylaşılmamalıdır.**

### 7.3 Hash ve kesin eşitlik

- `phys_hash`: Zobrist yöntemi. Sabit tohumlu (seed) bir `splitmix64` ile
  üretilen `u128` tablolar kullanılır: `ROBOT[tile][dir]`, `STAR[tile]`,
  `COLOR[tile][color]`. Hareket, dönüş, boyama ve yıldız toplama hash'i
  XOR ile O(1) günceller.
- `key_hash = mix(phys_hash, stack_hash(M))`.
- `CycleDetector { buckets: HashMap<u128, Vec<CycleSnapshot>> }`, burada
  `CycleSnapshot = { pos, dir, stars, colors, current, callers }`. `stars` ve
  `colors` paketli olduğu için bir kayıt yaklaşık 120 bayttır; stack
  kopyalanmaz.
- Hash eşleşince **kesin eşitlik** kontrol edilir. Stack karşılaştırması iki
  zinciri birlikte yürür: `NodeId`'ler eşitse zincirlerin geri kalanı da
  kesin olarak aynıdır (düğümler değişmez), dur. `depth`'ler farklıysa
  stack'ler farklıdır, dur. Aksi halde frame'leri karşılaştırıp bir üst
  düğüme geç. `NodeId`'ler farklı olup içerik aynı olabilir: aynı stack END
  onarımıyla ya da farklı bir push sırasıyla yeniden oluşmuş olabilir.

**Kesin eşitlik neden zorunlu:** Bir hash çakışmasının sonucu yanlış bir
*budama* olur, yani var olan bir çözüm kaçırılır. `finalize`'daki doğrulama
(§9.3) bunu yakalayamaz: o sadece *bulunan* çözümün çalışıp çalışmadığını
kontrol eder, kaçırılan dalları göremez. Tamlık (completeness) iddiası kesin
eşitliğe dayanır.

---

## 8. Aday üretimi

Aday üretimi iki ayrı adımdan oluşur ve bunlar kodda ayrı tutulur:

- **Generator:** Anlamsal olarak hangi hücreler mümkün?
- **Canonicalizer:** Bunlardan hangileri arama uzayında gereksiz bir
  eşdeğerin kopyası? (§8.5)

Tek istisna P-SYM'dir (§8.4): simetri, filtre olarak değil, doğrudan
çağrılabilir fonksiyon kümesi (`callable`) olarak üretilir, çünkü bu daha ucuz.

### 8.1 Frontier türleri ve maliyet

| Frontier | Adaylar | Maliyet |
|---|---|---|
| `OpenSlot{f, pc}` | `END` | +0 |
| | `Resolved{cond ∈ aktif koşullar, action}` | +1 |
| | `CondOnly{c}`, `c` ertelenen koşul | +1 |
| `NeedAction{f, pc, c}` | `Resolved{Is(c), action}` ile yer değiştirme | +0 |

`used + maliyet > budget` olan aday üretilmez. `OpenSlot`'ta bütçe dolduysa
geriye sadece `END` kalır.

- **P-STEPCUT:** `M.steps == MAX_STEPS` ise:
  - `NeedAction` → dal açılmadan `NotFound`.
  - `OpenSlot` → yalnızca `END` üretilir.

  (*Kanıt:* Bir sonraki değerlendirilecek dolu hücre `MAX_STEPS + 1`. adım
  olur ve R-STEP gereği `StepLimit` ile ölür. `END` adım saymaz, çalışan
  frame'i bitirir ve dönüşteki çalıştırma ancak başka bir dolu hücreye
  ulaşırsa ölür; o yüzden `END` yaşayabilir.)

### 8.2 Koşullar (P-COLOR)

`cur = M.colors[M.pos]`, `PC = possible_colors`.

- `|PC| == 1`: aktif koşul yalnızca `Any`; `CondOnly` üretilmez.
  (*Kanıt:* tek bir renk varsa `Is(c)` ile `Any` her zaman aynı davranır.
  Aynı maliyetli kanonik temsil `Any`'dir.)
- `|PC| ≥ 2`: aktif koşullar `{Any, Is(cur)}`; ertelenen koşullar
  `{c ∈ PC : c ≠ cur}`.
  (*Kanıt:* `PC` dışındaki bir renk hiçbir zaman oluşamaz, o koşuldaki bir
  hücre hiç çalışmaz. Silinirse maliyet düşer, dolayısıyla en küçük çözümde
  bulunmaz.)

`Any` ile `Is(cur)` birleştirilmez: şu an aynı davranırlar, ama o slot ileride
başka bir renkte tekrar çalışabilir.

`config.lazy_conditions == false` ise ertelenen her `c` için `CondOnly{c}`
yerine bütün `Resolved{Is(c), action}` hücreleri doğrudan (eager) üretilir
(§8.7). Bu hücreler şu an atlanır, aksiyonları ileride tetiklendiklerinde
anlam kazanır.

### 8.3 Aksiyonlar

Hücrenin koşulu `cond` (`NeedAction`'da `Is(c)`) için aday aksiyonlar:

```text
Forward, TurnLeft, TurnRight,
Paint(x)  for x in allowed_paints,
Call(g)   for g in callable(state)                   (§8.4)
```

Filtreler:

- **P-PAINT:** `cond == Is(x)` ise `Paint(x)` üretilmez. (*Kanıt:* komut ancak
  kare zaten `x` renkliyken çalışır, yani her zaman etkisizdir. Silinirse
  maliyet ve adım sayısı düşer.) `Any: Paint(cur)` üretilir, çünkü ileride başka
  bir renkte çalışıp etkili olabilir.
- **P-DISABLED:** `cap[g] == 0` olan fonksiyon hiçbir zaman çağrılmaz.
  (*Kanıt:* motorda bu çağrı etkisiz ama adım sayıyor, R-RUN (232).)

### 8.4 Fonksiyon simetrisi (P-SYM)

- `introduced`: programda bir `Resolved{…, Call(g)}` hücresi **oluştuğu anda**
  `g` bu kümeye eklenir. Bu `OpenSlot`'ta da, `NeedAction` çözümünde de olur.
  `CondOnly` bir fonksiyonu tanıtmaz. `F1` baştan tanıtılmış sayılır
  (`introduced = 0b00001`).
- Kapasite sınıfları: `F2..F5` arasında `cap > 0` olanlar kapasiteye göre
  gruplanır. `F1` hiçbir sınıfa girmez, çünkü giriş noktası olduğu için
  diğerleriyle yer değiştiremez.
- `callable(state) = introduced ∪ { her sınıfta henüz tanıtılmamış en küçük indeksli fonksiyon }`.

Örnekler:
- `cap = [6, 6, 0, 6, 0]` (katalogdaki #2973): başta `{F1, F2}`; `F2`
  tanıtıldıktan sonra `F4` de çağrılabilir.
- `cap = [7, 4, 2, 4, 2]`: sınıflar `4 → [F2, F4]`, `2 → [F3, F5]`. Başta
  `{F1, F2, F3}`.

*Kanıt:* Aynı kapasiteli iki fonksiyonun isimleri (ve bütün çağrıları)
değiştirilirse, geçerli ve aynı maliyetli bir program elde edilir ve
çalıştırma değişmez. Bir çözümde her sınıf, fonksiyonların ilk tanıtılma
sırasına göre yeniden adlandırılabilir. Bu sıra çalıştırmanın kendisi
tarafından belirlenir, dolayısıyla yeniden adlandırılmış program bu kuralı
sağlar ve arama tarafından bulunur. Farklı kapasiteli fonksiyonlar için bu
geçerli **değildir**: 4 slotluk bir gövde 2 slotluk bir fonksiyona sığmayabilir.

### 8.5 Yerel eşdeğerlik budamaları (canonicalizer)

Hücre `i` indeksine yerleştirildikten ya da çözüldükten sonra
`is_locally_canonical(fn, i)` çağrılır ve yalnızca `i`'yi içeren pencerelere
bakar: `[i-2, i+2]`. `NeedAction`'da sağdaki komşular zaten dolu olabilir, bu
yüzden iki yöne de bakılır.

- **P-TURN:** Aynı fonksiyonda ardışık `Resolved` dönüş hücreleri **aynı
  koşula** sahipse şu kalıplar yasaktır:
  - `L R` ve `R L`: ikisi birlikte etkisiz, silinir.
  - `L L L` ve `R R R`: sırasıyla tek bir `R` ve tek bir `L` ile aynı.
  - `R R`: `L L` ile aynı (180°). Kanonik temsil `L L`.

  Böylece aynı koşullu bir dönüş dizisi yalnızca `L`, `R` ya da `L L` olabilir.

  *Kanıt:* Fonksiyonlara yalnızca baştan girildiği için `i+1` hücresi her
  zaman `i` hücresinin hemen ardından değerlendirilir. Dönüş karenin rengini
  değiştirmez. Dolayısıyla aynı koşula sahip iki ardışık dönüş ya birlikte
  çalışır ya birlikte atlanır. Yeniden yazılmış hal aynı state'i daha az ya
  da eşit maliyetle ve daha az ya da eşit adımla üretir; adım sayısının
  azalması 20000 sınırını ihlal edemez.

  `CondOnly` hücreleri dönüş sayılmaz. Bunlar çözüldüğünde, `NeedAction`
  anında kontrol edilirler.
- **P-EMPTYFN:** `pc == 0` iken `END` üretilmez. (*Kanıt:* `F1` için bu
  program hiçbir şey yapmaz. `g ≠ F1` için gövdesi boş bir fonksiyona yapılan
  her çağrı etkisizdir ama bir slot harcar. Bu çağrılar silinirse maliyet
  düşer.)

### 8.6 Sıralama (normatif değil)

Sıralama doğruluğu etkilemez, sadece son bütçe turunda çözüme ne kadar hızlı
ulaşıldığını etkiler: başarısız olan `1..K-1` bütçe turları her zaman tamamen
taranır. v1'de sabit bir sıra yeterli:

```text
OpenSlot:   Any:Forward, cur:Forward, Any:Call(tanıtılmış), Any:TurnLeft, Any:TurnRight,
            cur:(aynı sıra), Any:Call(yeni), Paint…, CondOnly…, END
NeedAction: Forward, Call(tanıtılmış), TurnLeft, TurnRight, Call(yeni), Paint…
```

### 8.7 `Config`: ablation bayrakları

```rust
struct Config {
    lazy_conditions:   bool,   // CondOnly / NeedAction (§8.2)
    function_symmetry: bool,   // P-SYM (§8.4)
    peephole:          bool,   // P-TURN, P-PAINT, P-EMPTYFN (§8.3, §8.5)
    cycle_detection:   bool,   // §7
    step_cut:          bool,   // P-STEPCUT (§8.1)
}   // varsayılan: hepsi true
```

**Kural:** Bir bayrağı kapatmak optimizasyonu kaldırır ve arama uzayını
büyütür; **hiçbir zaman bir dalı yasaklamaz**. Her `Config` aynı en küçük
maliyeti bulmalıdır (`t_config_equivalence`).

| Bayrak `false` iken | Davranış |
|---|---|
| `lazy_conditions` | `CondOnly{c}` yerine her ertelenen `c` için bütün `Resolved{Is(c), action}` hücreleri üretilir (eager). `NeedAction` hiç oluşmaz. Bu hücreleri **yasaklamak** değil, **önceden açmak** demektir; yasaklamak çözüm kaybettirirdi. |
| `function_symmetry` | `callable` = `cap > 0` olan bütün fonksiyonlar. |
| `peephole` | P-TURN, P-PAINT ve P-EMPTYFN uygulanmaz. |
| `cycle_detection` | Döngüler `StepLimit` ile ölür (yavaş ama doğru). |
| `step_cut` | Aday üretimi normal devam eder; dallar bir sonraki adımda `StepLimit` ile ölür. |

P-COLOR, P-DISABLED ve P-CONN bayrakla kapatılmaz. Bunlar temsilin kendisini
tanımlar (olmayan bir renk, olmayan bir fonksiyon, ulaşılamayan bir yıldız).

---

## 9. Arama

### 9.1 Dış döngü: bütçeye göre derinleştirme (IDDFS)

```text
solve(level, config, limits):
    if P-CONN başarısız: return Unsolvable(Disconnected)
    for budget in 0 ..= sum(cap):
        root = SearchState {
            program: boş (bütün fonksiyonlar açık, len = 0, ended = false),
            machine: başlangıç state'i, current = (F1, 0), callers = None, steps = 0,
            used: 0, introduced: {F1},
        }
        arena.clear()
        match search(root, budget):
            Found(s)  → return Solved(finalize(s))
            Timeout   → return Timeout
            NotFound  → continue
    return Unsolvable(Exhausted)    # hiçbir bütçede çözüm yok (motor semantiği altında)
```

`budget = 0` turu, yıldızı olmayan bulmacaları boş programla çözer. Yıldızlı
bir bulmacada P-EMPTYFN gereği hemen biter.

### 9.2 İç döngü: DFS

```text
search(self, s: SearchState, budget) -> Result<Option<SearchState>, Timeout>:
    self.limits.check()?                             # zaman ve node sınırı
    self.stats.search_nodes += 1
    let mut s = s
    let mut cycles = CycleDetector::new()            # §7.2
    match normalize(self, &mut s, &mut cycles):
        Solved         → return Ok(Some(s))
        Dead(reason)   → self.stats.dead(reason); return Ok(None)
        OpenSlot{f,pc} →
            for cand in self.open_candidates(&s, f, pc, budget):   # §8, sıralı ve filtrelenmiş
                mark = self.arena.mark()             # adaydan ÖNCE (END onarımı düğüm üretir)
                child = s                            # Copy
                apply(&mut child, cand)              # cells[len] = …, len += 1  |  ended = true
                if cand == END: S-REBUILD(self.arena, &mut child.machine, f, pc)
                r = self.search(child, budget)
                self.arena.truncate(mark)
                if r? is Some: return r
            return Ok(None)
        NeedAction{f,pc,c} →
            if P-STEPCUT uygulanıyorsa: return Ok(None)
            for act in self.need_candidates(&s, f, pc, c):
                mark = self.arena.mark()
                child = s
                child.program.fns[f].cells[pc] = Resolved{Is(c), act}
                if act == Call(g): child.introduced |= bit(g)
                r = self.search(child, budget)
                self.arena.truncate(mark)
                if r? is Some: return r
            return Ok(None)
```

`apply` bir `Call(g)` hücresi eklediğinde `introduced |= bit(g)` ve
`used += 1` yapar; `CondOnly` eklediğinde yalnızca `used += 1`.

### 9.3 `finalize`

```text
finalize(s):
    assert (INV-FIN) bütün hücreler Resolved      # debug_assert
    physical = her f için cells[..len] ++ null * (cap[f] - len)
    r = REFERENCE_RUN(physical)
    assert r == SUCCESS                            # her zaman, release derlemede de
    return Solution { physical, cost: s.used, steps: r.steps }
```

**INV-FIN:** İlk bulunan çözümde `CondOnly` hücre kalamaz. (*Kanıt:* Hiç
tetiklenmemiş bir `CondOnly` her seferinde atlanmıştır. Silinirse davranış
aynı kalır, sadece adım sayısı ve maliyet 1 azalır. O zaman `budget - 1`
turunda bir çözüm olurdu, ama o tur zaten başarısız oldu. Çelişki.)
Tetiklenirse bir bug var demektir.

Açık kalmış fonksiyon sonları çıktıda `null` olur. Bunlar hiçbir zaman
ulaşılmadığı için hiçbir etkileri yoktur ve maliyete sayılmazlar.

Bu iki yorumlayıcı düzeni (arama için `normalize`, doğrulama için
`REFERENCE_RUN`) solver'ın emniyet kemeridir: `normalize`'da bir bug olsa bile
yanlış bir çözüm dışarı çıkmaz.

### 9.4 `SearchStats`

Her bulmaca için, bütçe turlarının toplamı olarak raporlanır. `Solver` içinde
durur, `SearchState` içinde **değil**.

| Sayaç | Ne zaman artar |
|---|---|
| `search_nodes` | Her `search` çağrısında. Ayrıca bütçe başına ayrı ayrı (`nodes_per_budget`). |
| `normalize_calls` | Her `normalize` çağrısında. |
| `instructions_evaluated` | Her `consume_step` çağrısında. **Node sayısı kadar önemli**: bir optimizasyon node'ları azaltıp normalize işini artırıyorsa duvar saati süresi beklendiği kadar düşmez. |
| `open_frontiers`, `need_action_frontiers` | İlgili frontier döndüğünde. |
| `candidates_generated`, `candidates_searched` | Üretilen ve özyinelemeye giren aday sayısı. |
| `dead_crash`, `dead_step_limit`, `dead_out_of_instructions`, `dead_loop` | `normalize` ilgili sebeple öldüğünde. |
| `prune_budget`, `prune_step_cut`, `prune_symmetry`, `prune_peephole` | İlgili kural bir adayı elediğinde. |
| `ends_selected`, `condonly_created`, `condonly_resolved` | İlgili karar uygulandığında. |
| `stack_pushes`, `tail_calls`, `returns`, `stack_rebuilds`, `stack_nodes_rebuilt` | Stack işlemlerinde. |
| `max_search_depth`, `max_call_depth` | En büyük değer. |

---

## 10. Doğruluk özeti

**Sağlamlık (soundness).** Döndürülen her program motorda `SUCCESS` verir:
L1–L5 gereği `normalize` motoru birebir simüle eder, ve buna ek olarak her
çözüm `REFERENCE_RUN` ile (§9.3) ve Dart motoruyla (§12) ikinci kez
doğrulanır.

**Tamlık ve optimallik.** Maliyeti `K` olan bir çözüm varsa, `search(budget = K)`
maliyeti `K` olan bir çözüm bulur (zaman sınırı olmadığı varsayımıyla; her
`Config` için). *İspat taslağı:* En küçük bir çözüm `Q` alınır. L1 ile sola
sıkıştırılır, P-SYM ile fonksiyonları yeniden adlandırılır, P-TURN, P-COLOR ve
P-PAINT yeniden yazımları uygulanır. Bu yeniden yazımlar maliyeti artırmaz ve
davranışı korur. Sonra arama, `Q`'nun hücrelerini takip ederek ilerler:

- Her `OpenSlot`'ta `Q`'nun o slottaki hücresi ya aktif bir koşulla adaydır,
  ya ertelenen bir koşulla `CondOnly` olarak aday olur (aksiyonu daha sonra
  `NeedAction`'da seçilir; `lazy_conditions` kapalıysa doğrudan aday olur),
  ya da `null`'dır ve bu `END` adayına karşılık gelir.
- P-EMPTYFN, P-STEPCUT ve INV-FIN, `Q`'nun en küçük ve başarılı olmasıyla
  uyumludur.
- L7, `Q`'nun yolunu kesmez: `Q` başarıya ulaştığı için çalıştırmasında
  tekrar eden bir state yoktur.

Bütçe `0..K-1` turları tamamen tarandığı için, bulunan ilk çözüm en küçüktür.

---

## 11. Test planı

| Test | Neyi kilitler |
|---|---|
| `t_level_*` | Katalog yüklenir; sınır aşan, düzensiz satırlı ve başlangıcı boşlukta olan bulmacalar `Unsupported` döner, panic olmaz. |
| `t_ref_*` | `REFERENCE_RUN`, tutorial bulmacalarında (`test/tutorial_levels_test.dart`'taki programlar) Dart ile aynı sonucu verir. |
| `t_step_limit_boundary` | State doğrudan kurulur: `steps = 19999` iken son yıldızı alan `Forward` → `Solved`, `steps = 20000`. `steps = 20000` iken aynı komut → `Dead(StepLimit)`, robot hareket etmemiş, yıldız yerinde. Aynı test koşulu tutmayan bir komut ve atlanan bir `CondOnly` için de yapılır. |
| `t_frontier_no_step` | `OpenSlot` ve eşleşen `NeedAction` döndüğünde `pc` ve `steps` değişmemiştir. |
| `t_tail_call`, `t_non_tail_call` | R-TAIL: `F1: [Forward, Call F1]` arena'ya düğüm eklemez. Devamı olan çağrı çağıranı askıya alır. |
| `t_diff_random` | **T-DIFF:** Rastgele, tamamen dolu fiziksel programlar (sabit tohum, ≥ 10⁵ adet) katalogdaki bulmacalarda hem `REFERENCE_RUN` hem `normalize` ile çalıştırılır. Sonuç, `steps` ve son state aynı olmalı (L4). |
| `t_loop_*` | Tail recursion döngüsü `Dead(Loop)` olarak yakalanır. Derin non-tail recursion yanlışlıkla budanmaz, `Dead(StepLimit)` ile biter. Yıldız alan bir "döngü" döngü sayılmaz. |
| `t_cycle_exact_equality` | Aynı hash'e sahip ama farklı iki state (hash elle zorlanarak) döngü sayılmaz. |
| `t_rebuild_middle` | §6.3'teki ulaşılabilir örnek: END'den sonra `[C@j]` kalır, hash zinciri ve `depth` yeniden hesaplanmıştır. |
| `t_zobrist_*` | Boyama ve yıldız toplama `phys_hash`'i değiştirir; geri boyama eski hash'e döner. |
| `t_p_sym`, `t_p_turn`, `t_p_paint`, `t_p_color`, `t_p_emptyfn`, `t_p_stepcut` | Her budama kuralı hem pozitif hem negatif örnekle. `t_p_sym` farklı kapasiteli fonksiyonların birleştirilmediğini de kontrol eder. |
| `t_p_turn_needaction` | `Red:?, Red:R` durumunda `?` için `L` üretilmez. |
| `t_e2e_tutorials` | Tutorial bulmacaları çözülür, maliyetleri beklenen en küçük değerlere eşit. |
| `t_e2e_bruteforce` | Küçük, elle kurulmuş bulmacalarda (toplam kapasite ≤ 4) bütün fiziksel programları deneyen saf bir kaba kuvvet ile aynı en küçük maliyet bulunur. **Optimalliğin asıl testi.** |
| `t_config_equivalence` | Küçük bir bulmaca setinde her `Config` kombinasyonu aynı en küçük maliyeti bulur. |
| Dart: `solver_solutions_test.dart` | §12. |

---

## 12. Çıktı formatı ve Dart doğrulaması

`solutions.json`:

```json
{
  "solver": "robozzle-solver 0.1.0",
  "maxSteps": 20000,
  "config": { "lazyConditions": true, "functionSymmetry": true, "peephole": true, "cycleDetection": true, "stepCut": true },
  "results": [
    {
      "sourceId": 195,
      "status": "solved",
      "cost": 7,
      "steps": 1234,
      "program": [
        ["forward", "red:turnLeft", "callF2", null, null, null, null],
        ["forward", "blue:callF1", null, null],
        [null, null, null, null],
        [],
        []
      ],
      "stats": { "millis": 12, "searchNodes": 45678, "instructionsEvaluated": 912345, "nodesPerBudget": [1, 1, 5, 40] }
    },
    { "sourceId": 53, "status": "timeout", "stats": { "millis": 60000, "searchNodes": 123456789 } },
    { "sourceId": 999, "status": "unsupported", "reason": "function capacity 13 exceeds 12" }
  ]
}
```

- Her fonksiyon dizisinin uzunluğu `cap[f]`'ye eşittir; boş slotlar `null`.
- Komut yazımı: `"<koşul>:<aksiyon>"`. Koşul `Any` ise koşul kısmı yazılmaz.
  Koşul adları `red | green | blue`; aksiyon adları Dart'taki `ActionType`
  isimleriyle birebir aynı: `forward`, `turnLeft`, `turnRight`, `paintRed`,
  `paintGreen`, `paintBlue`, `callF1` … `callF5`. Böylece Dart tarafında
  `ActionType.values.byName(...)` ile doğrudan parse edilebilir.
- `status` değerleri: `solved | timeout | unsolvable | unsupported`.
- `stats` alanları §9.4'teki sayaçların camelCase halidir.

**Dart testi** (`test/solver_solutions_test.dart`): Katalog ve
`solutions.json` dosyaları `dart:io` ile okunur. Her `solved` kayıt için
program `RobotProgram` olarak kurulur ve `runToCompletion()` ile çalıştırılır.
Beklentiler:

- `status == RunStatus.success`
- `interpreter.stepsExecuted == kayıttaki steps`. Adım sayısının birebir
  tutması, iki semantiğin gerçekten aynı olduğunun en güçlü kanıtıdır.

`solutions.json` dosyası yoksa test atlanır (skip).

---

## 13. CLI

```text
solver <catalog.json> [--id <sourceId>]... [--all]
       [--timeout-ms <ms>]   (bulmaca başına, varsayılan 10000)
       [--node-limit <n>]
       [--out <solutions.json>]
       [--no-lazy-conditions] [--no-function-symmetry] [--no-peephole]
       [--no-cycle-detection] [--no-step-cut]
```

Her bulmaca için tek satır ilerleme çıktısı; sonunda zorluk seviyesine göre
özet: çözülen sayısı, ortalama süre, toplam `search_nodes` ve
`instructions_evaluated`.

Paralellik: v1'de yok. v1.5'te bulmacalar arası paralellik (`rayon`) eklenir;
bu kolay ve güvenli, çünkü bulmacalar birbirinden bağımsız (her iş parçacığı
kendi `Solver`'ını kullanır).

---

## 14. Modül yapısı ve uygulama sırası

Modül listesi, bağımlılıklar ve uygulama sırası artık
[`SPEC.md`](SPEC.md) Ek B'de (Appendix B) tanımlıdır. Özeti: `types.rs`,
`puzzle.rs`, `program.rs`, `machine.rs`, `stack.rs`, `reference.rs`,
`normalize.rs`, `canonical.rs`, `search.rs`, `stats.rs`, `lib.rs`, `main.rs`.

Sıranın mantığı değişmedi: önce kahin (`reference.rs`), sonra `normalize`
(T-DIFF ile), sonra en basit arama (eager koşullar), ardından her
optimizasyon ayrı bir adımda eklenir ve etkisi `BENCHMARKS.md`'ye yazılır.

---

## 15. v1 kapsamı dışında (ölçümden sonra karar verilecek)

- **Undo/trail (make/unmake).** Gerekçe §4.0. `SearchStats` kopyalamanın
  gerçek bir darboğaz olduğunu gösterirse yeniden değerlendirilir.
- **Global transposition table.** Gerekçe: bir kısmi programa arama ağacında
  tek bir yoldan ulaşılır, dolayısıyla tabloda eşleşme olmaz.
- **Yol kapsamlı döngü cache'i** (§7.2).
- **`function_mask_below`:** Arena düğümlerinde "bu zincirde fonksiyon `f`
  var mı?" bilgisini tutup S-REBUILD'i gerekmediğinde atlamak.
- İstatistiğe dayalı sıralama (killer/history), `--any` modu (en kısa değil,
  herhangi bir çözüm).
- Aynı bulmaca içinde paralel arama.
- Non-tail recursion için pushdown analizi.
- İkincil hedef: aynı maliyette en az adım.

---
---

<a id="english"></a>

# Robozzle Solver — Design Specification (v1.1) — English

This document explains **what the solver does and why it is correct**: the
rationale, proofs and alternatives behind each rule. **The normative
contract is [`SPEC.md`](SPEC.md)**: type and function names, exact
transition rules, test vectors and the output format live there. If the two
documents disagree, SPEC.md wins and both are fixed in the same change.
Names used here (`Level`, `Cond::Is`, …) are descriptive; code uses the
names from SPEC.md.

> **v1.2 — additions driven by measurement.** The first catalog run showed
> two things. (1) Nearly all search time went into running non-tail
> recursion that only grows the stack for 20 000 steps; such a run never
> repeats a state exactly, so loop detection could not catch it. **C-PUMP**
> (SPEC §12): when the same physical state and current frame recur and the
> earlier caller chain's top node is still on the chain, everything in
> between repeats forever. Speed went up ~1 200×. (2) `Any:X` and
> `<current color>:X` behave identically when placed; they differ only once
> the slot runs on another color. **D-PENDING / D-CHOOSE** (SPEC §13) defer
> that choice until it is observable, like `CondOnly`, halving the active
> candidates. Two cheap rules come with it: **P-CRASH** (no `Forward` that
> would immediately leave the board) and **P-ENDDEAD** (`END` with no
> suspended caller ends the program). All of them can be switched off with
> `Config`; results are in [`BENCHMARKS.md`](BENCHMARKS.md).
>
> **v1.3 — heuristic phase.** Exact search multiplies its work by ~10 per
> extra slot, so it cannot go beyond 10–11 slots, while hard puzzles need
> longer programs. Stockfish's strength comes from trying good moves first;
> we add the same principle **without weakening the optimality guarantee**
> (SPEC §17). The exact search uses half of the node budget first; if it finds
> nothing, *Limited Discrepancy Search* runs on the same tree: at each
> decision the children are run once and ranked by stars collected and
> distance to the nearest star; the search tries the best path first, then
> deviations from it. The solution found is verified, shrunk by deleting
> unnecessary cells, and the remaining budget looks for a shorter one. The
> result is reported as `optimal: true` (proven minimal) or `optimal: false`
> with a `lowerBound`. No randomness, budgets are node counts: the result is
> the same on every machine.
>
> Failure analysis showed two more things: the budget split between exact
> and heuristic search is a trade-off (1:1 by measured marginal value), and
> failed searches often reach programs that collect over 90 % of the stars
> and then die, and forget them. The **history heuristic** (as in chess
> engines) remembers the best progress seen below each decision, dead
> branches included, and tries those decisions first. It only reorders;
> 444 → 461.
>
> **v1.4 — why no conflict learning, and what replaced it.** The proposal
> to add SAT-style nogood learning and backjumping was measured by an
> adversarial review: in lazy synthesis every decided cell executes before
> the failure, and every executed RoboZZle instruction affects the robot's
> pose or the control flow. Over 1.82 M dead leaves, sound reason sets held
> 98.7–99.6 % of the path's decisions, 100 % in paint-free puzzles;
> backjumping degenerates to chronological backtracking (0.1–1.8 % saved).
> Instead, new instances of the same principles ("do not decide until it is
> observable", "do not generate what a minimal solution cannot contain")
> were added: **anonymous auxiliary functions** (name symmetry across
> capacity classes, with the INV-FIT matching), **D-DEFER-SET** (the
> deferred color itself is deferred), **P-SINGLE** (an auxiliary function
> never has exactly one cell) and **P-RESERVE** (every called auxiliary
> function reserves at least 2 slots: the first sound lower bound).
>
> **v1.5 — measurement discipline.** The product mode shares one node
> budget between exact and heuristic search, so a change can help one and
> hurt the other while the total barely moves. Every change is therefore
> measured on the benchmark it targets: **EXACT** (`--exact-only`: proven
> optima and lower bounds), **FINDER** (`--heuristic-only`: solutions found)
> and **PRODUCT** (the default mode: what users get). Development uses a
> fixed dev set of 150 puzzles at 5 M nodes; the full catalog only confirms
> a change.
>
> **v1.6 — decaying history and local repair.** Telemetry on the dev set
> showed two things. (1) The history heuristic's plain maximum keeps pulling
> forward a decision that once led far and has disappointed ever since.
> **Decaying history** (SPEC §17.3): a subtree that beats the entry raises
> it at once (a bonus), one that does worse pulls it a quarter of the way
> down (a malus). Stockfish-style gravity tables, contextual tables keyed by
> the previous decision or the robot's situation, and other decay rates were
> measured too; the simplest won (BENCHMARKS.md). (2) LDS often reaches
> programs that die one or two cells away from a solution it would reach
> only after many more discrepancies. **Local repair** (SPEC §17.5) searches
> the edit neighbourhood of the best programs directly: replace, delete or
> insert one cell, and pairs of edits. Each candidate is simulated from the
> point where it first diverges, without re-running the shared prefix.
> Repair uses nodes but never prunes or reorders, and every program it
> finds is verified on the reference interpreter like any heuristic
> solution. On the dev set (5 M nodes): FINDER 26 → 40, PRODUCT 20 → 29;
> on the full catalog (20 M nodes): 478 → 521 solved, 393 → 399 proven
> minimal, 4-function puzzles 18 → 34.

Rule IDs (`R-*`, `N-*`, `S-*`, `INV-*`, `P-*`, `T-*`) are referenced from code
comments and test names. For example, the code implementing a pruning rule
carries a `// P-TURN` comment and its tests are named `t_p_turn_*`.

---

## 0. Goal and principles

**Goal:** for every puzzle in `assets/levels_catalog.json` (and every puzzle
made in the editor), find a program that succeeds in the app's engine
([`lib/engine/interpreter.dart`](../lib/engine/interpreter.dart)) and uses the
**fewest occupied slots**.

- **Primary objective:** minimize the number of non-empty slots.
- **Constraint:** the real engine's 20000-step limit. It is a constraint, not
  an objective.
- **Secondary objective (not in v1):** fewer steps at equal slot count.

Four principles override everything else:

1. **Engine semantics are sacred.** Every program the solver reports as a
   solution MUST produce `RunStatus.success` in the Dart engine (§2, §10).
2. **Prune only with proof.** A branch may be cut only if it can be *proven*
   that it contains no minimal solution. "Looks bad" is never a reason to
   prune; heuristics may only change the *order* in which branches are
   explored (§8.6).
3. **Determinism.** The same input always yields the same output. Search
   decisions never depend on `HashMap` iteration order.
4. **Measurability.** Every optimization can be switched off with a `Config`
   flag, and its effect is measured with `SearchStats` (§8.7, §9.4).
   Switching an optimization off never loses a solution; it only makes the
   search bigger.

---

## 1. Terms

| Term | Meaning |
|---|---|
| Function `F1..F5` | Indices `0..4` in code. `F1` is the entry point. |
| Capacity `cap[f]` | Number of slots the puzzle gives that function (`slotsPerFunction`). `0` means the function is not available. |
| Physical program | For each function, an array of length `cap[f]` whose elements are `null` or an instruction. This is Dart's `RobotProgram`. |
| Partial program | What the search has decided so far (§4.2). |
| Step | The engine's `stepsExecuted` counter. +1 for every **non-empty** slot evaluated (§2). |
| Frontier | The point where execution reaches a part of the program that has not been decided yet, and stops. |
| Cost | Number of occupied slots in the program. |
| Current frame | The frame whose instructions are running (`current`). |
| Suspended frame | A frame that made a call and is waiting for it to return (in the `callers` chain). |

---

## 2. Reference semantics (engine contract)

The algorithm below is an **exact** summary of `interpreter.dart`. Numbers in
parentheses are line numbers in that file (commit `37b5ede`). If the engine
changes, this section and `reference.rs` change together.

```text
REFERENCE_RUN(level, program):                                 # R-RUN
    pos, dir   = level.start
    colors     = level's initial tile colors
    stars      = level's stars
    steps      = 0
    stack      = [(F1, 0)]  if cap[F1] > 0 else []             (112)
    if stars.is_empty(): return SUCCESS                        (111)

    loop:
        if stack.is_empty():                                   (185)
            return SUCCESS if stars.is_empty() else OUT_OF_INSTRUCTIONS
        (f, i) = stack.top
        if i >= cap[f]:  stack.pop(); continue                 (193)   # R-POP
        slot = program[f][i];  stack.top.i += 1
        if slot == null: continue                              (202)   # R-NULL
        steps += 1                                             (206)   # R-STEP
        if steps > MAX_STEPS: return STUCK                     (207)
        if slot.cond != Any and colors[pos] != slot.cond:      (221)   # R-COND
            continue
        match slot.action:
            Call(g):
                if cap[g] == 0: continue                       (232)
                if program[f][stack.top.i ..] all null:        (240)   # R-TAIL
                    stack.pop()
                stack.push((g, 0))
            TurnLeft:  dir = (dir + 3) % 4
            TurnRight: dir = (dir + 1) % 4
            Paint(c):  colors[pos] = c
            Forward:                                           (271)
                n = neighbor(pos, dir)
                if no n (off grid or gap): return CRASHED      (279)
                pos = n
                if stars.contains(n): stars.remove(n)
                if stars.is_empty(): return SUCCESS            (288)
```

`MAX_STEPS = 20000` (93). Every screen in the app uses the default.

Critical points (each has a test, §11):

- **R-STEP:** The step-limit check happens **before** the condition check
  **and** before the instruction runs. The 20001st non-empty slot has no
  effect at all: the robot does not move, no star is collected.
  Condition-mismatched instructions count as steps, and so do calls to a
  function with `cap = 0`. `null` slots and function returns do not.
- **R-TAIL:** If all of the caller's remaining slots are `null`, the caller's
  frame is popped before the push. The only observable effect is stack depth;
  behavior is unchanged, because without it the frame would have popped on
  return without consuming a step.
- Stack depth is unbounded. The solver does **not** add a limit either. (In
  practice depth is bounded by the step count, i.e. 20000.)
- A star is collected only when the robot **enters** its tile. No catalog
  puzzle has a star on the start tile; if one did, that star would not count
  as collected until the robot re-entered the tile.

---

## 3. Input and preprocessing

### 3.1 Input and supported limits

Each entry has `sourceId`, `rows` (list of strings), `startRow`, `startCol`,
`startDirection` (`up|right|down|left`), `slotsPerFunction` (5 numbers) and
`allowedCommands` (paint bitmask: `1` = red, `2` = green, `4` = blue).

Characters: `' '` or `'.'` is a gap; `r g b` is a colored tile; `R G B` is
the same color with a star on it.

The solver's limits are chosen to cover both the catalog and the app's
editor ([`editor_screen.dart:44-45`](../lib/screens/editor/editor_screen.dart)):

| Constant | Value | Largest in catalog | Editor allows |
|---|---|---|---|
| `MAX_TILES` (`rows × cols`) | 256 | 192 (12×16) | 196 (14×14) |
| `MAX_FUNCTION_SLOTS` | 12 | 10 | 12 |

**Validation:** when loading each puzzle, the loader checks that all rows have
the same length; the start tile is inside the grid and not a gap;
`cap[F1] > 0`; there are no unknown characters; and the limits above are not
exceeded. If a check fails, that puzzle returns `Unsupported(reason)`. **It
never silently truncates and never panics**; the remaining puzzles keep
being solved.

A puzzle with no stars (possible in the editor) is valid: the empty program
solves it (§9.1).

### 3.2 Precomputed static data (`Level`)

| Field | Definition |
|---|---|
| `TileId` | `row * cols + col`, `u8` (≤ 255). Gaps also get a `TileId` but have `is_tile = false`. |
| `neighbor[tile][dir]` | `Option<TileId>`. `None` if off the grid or a gap. |
| `init_colors` | Initial colors, `PackedColors` (§4.3). |
| `init_stars` | Set of star tiles, `StarSet = [u64; 4]` bitset. |
| `allowed_paints` | Set of colors derived from the `allowedCommands` bitmask. |
| `possible_colors` | `{colors initially on the grid} ∪ allowed_paints` (§8.2). |
| `cap[0..5]` | Function capacities. |
| `classes` | Capacity classes for F2..F5 (§8.4). |

Direction encoding: `Up = 0, Right = 1, Down = 2, Left = 3`.
`turn_left(d) = (d + 3) % 4`, `turn_right(d) = (d + 1) % 4`.

### 3.3 Static checks

- **P-CONN:** If any star lies outside the set of tiles reachable from the
  start tile (BFS), the puzzle returns `Unsolvable(Disconnected)` and search
  never starts. Painting does not change the grid's shape, so this check runs
  once.

---

## 4. Data structures

### 4.0 Architecture: shared context vs. branch state

There are two kinds of data, and they must not be mixed:

```rust
// One per search. Never copied into branches.
struct Solver {
    level: Level,          // static puzzle (§3.2)
    config: Config,        // ablation flags (§8.7)
    limits: Limits,        // time and node limits
    arena: StackArena,     // suspended frames (§6)
    stats: SearchStats,    // counters (§9.4)
}

// A branch's complete semantic state. Copy; copied for every child branch.
#[derive(Clone, Copy)]
struct SearchState {
    program: PartialProgram,
    machine: Machine,
    used: u8,          // cost: number of Resolved + CondOnly cells
    introduced: u8,    // bitmask: functions for which a call cell exists (§8.4)
}
```

**Copy-make.** Opening a child branch means copying the `SearchState` (no
heap, a few hundred bytes). No undo/trail log is kept. The one exception is
the arena, which is rewound with `mark()` / `truncate(mark)` (§6.1).

*Why not undo:* in a chess engine a move changes a few squares and the search
moves straight to the next node. Here each node's `normalize()` may execute
thousands of steps. A trail would have to log every paint and every star
collection inside that hottest loop. Copying pays once per node instead. If
`SearchStats` shows copying to be a bottleneck, this decision is revisited
(§15).

`Config` and `SearchStats` are never part of `SearchState`. If they were,
every copy would also copy the counters and they would lose their meaning.

### 4.1 Instructions

```rust
enum Color { Red, Green, Blue }
enum Cond  { Any, Is(Color) }
enum Action { Forward, TurnLeft, TurnRight, Paint(Color), Call(FnId) }
```

### 4.2 Partial program

```rust
#[derive(Clone, Copy)]
enum Cell {
    Resolved { cond: Cond, action: Action },
    CondOnly { cond: Color },          // condition chosen, action not yet
}

#[derive(Clone, Copy)]
struct FunctionDraft {
    cells: [Cell; MAX_FUNCTION_SLOTS], // only cells[..len] is meaningful
    len: u8,                           // number of decided cells (left-packed)
    ended: bool,                       // true: everything after len is definitely empty (END)
}

#[derive(Clone, Copy)]
struct PartialProgram { fns: [FunctionDraft; 5] }
```

The representation has **no** `UNKNOWN` or `EMPTY` cell: if
`len < cap && !ended`, the next slot is undecided; if `ended`, everything
from that point on is empty.

Definitions:

- **Closed function:** `closed(f) := fns[f].ended || fns[f].len == cap[f]`.
- **Exhausted frame:** `exhausted(f, pc) := pc == fns[f].len && closed(f)`.
  Such a frame definitely has no instruction left to run.
- Physical form: `physical(f) = cells[..len] (all Resolved) ++ [null; cap[f] - len]`.

**Lemma L1 (left packing).** Moving the `null` slots of a function to its end
does not change behavior. `null` slots are skipped and do not count as steps
(R-NULL). R-TAIL only asks "is any non-empty slot left after this one?", and
the answer is unchanged by the move. Functions are only entered at their
start; no instruction jumps to a slot index. So every physical program has a
unique left-packed form with the same behavior and the same cost, and
searching only left-packed forms loses no solution.

### 4.3 Machine

```rust
#[derive(Clone, Copy)]
struct Machine {
    pos: TileId,
    dir: u8,
    colors: PackedColors,       // 2 bits per tile → 64 bytes
    stars: StarSet,             // [u64; 4] → 32 bytes
    star_count: u16,
    steps: u32,
    current: Option<Frame>,     // the running frame; its pc advances with every instruction
    callers: Option<NodeId>,    // suspended frames, a persistent chain in the arena (§6)
    phys_hash: u128,            // Zobrist hash of pos, dir, stars, colors (§7.3)
}

#[derive(Clone, Copy)]
struct Frame { f: u8, pc: u8 }
```

The stack is **not copied**: `Machine` holds only the `current` frame and a
`NodeId` pointing to the top of the `callers` chain. The chain itself lives,
immutable, in the arena.

---

## 5. `normalize()`: the execution layer

`normalize(solver, state, cycles) -> Outcome` advances the machine **in
place** under the partial program. **It never changes the program and makes
no decisions.** Synthesis (building the program) belongs to the search layer
alone (§9); this boundary must not be broken.

```rust
enum Outcome {
    Solved,
    Dead(DeadReason),                   // Crash | StepLimit | OutOfInstructions | Loop
    OpenSlot   { f: u8, pc: u8 },       // pc == len(f), function not closed
    NeedAction { f: u8, pc: u8, cond: Color },
}
```

```text
normalize(P, M, cycles):                                        # N-*
    loop:
        if M.star_count == 0: return Solved                     # N-SOLVED
        if M.current is None: return Dead(OutOfInstructions)
        (f, pc) = M.current

        if pc == len(f):                                        # N-END
            if closed(f): pop(M); continue                      # same as R-POP
            return OpenSlot{f, pc}                              # NO STEP, pc NOT ADVANCED

        match P.fns[f].cells[pc]:

            CondOnly{c}:                                        # N-CONDONLY
                if M.colors[M.pos] == c:
                    return NeedAction{f, pc, c}                 # NO STEP, pc NOT ADVANCED
                consume_step(M)?                                # limit exceeded → Dead(StepLimit)
                M.current.pc += 1
                continue                                        # condition false, skip

            Resolved{cond, action}:                             # N-RESOLVED
                consume_step(M)?                                # R-STEP: limit FIRST
                M.current.pc += 1
                if cond == Is(c) and M.colors[M.pos] != c: continue
                match action:
                    Forward:
                        n = neighbor[M.pos][M.dir]
                        if n is None: return Dead(Crash)
                        move(M, n)                              # collect star if any, update hash
                    TurnLeft / TurnRight: turn(M)
                    Paint(c): paint(M, c)
                    Call(g):
                        call(P, M, g)                           # §6.2, includes R-TAIL
                        if config.cycle_detection and cycles.observe(M) == Repeated:
                            return Dead(Loop)                   # §7

consume_step(M) -> Result<(), DeadReason>:                      # the only step counter
    M.steps += 1
    if M.steps > MAX_STEPS: Err(StepLimit) else Ok(())
```

**`consume_step` is the only function that touches the step counter.** No
other place in the code writes `steps += 1`.

Cells never call a function with `cap[g] == 0` (§8.3), so the branch at
R-RUN (232) needs no counterpart.

**Lemma L2 (stopping at a frontier).** At `OpenSlot` and `NeedAction` the
machine is in the state **immediately before** the slot is evaluated: no step
has been counted and `pc` has not advanced. Once the decision is made,
`normalize` evaluates the same slot from scratch, exactly as the engine
would. So every non-empty slot is counted exactly once. A `CondOnly` whose
condition does not match needs no action, so it is counted and skipped
right away.

**Lemma L3 (resuming from a frontier).** Execution up to the frontier never
read the cell being decided; if it had, it would have stopped there. So every
child branch can resume from a copy of the frontier machine instead of
re-running from the start.

**Lemma L4 (equivalence).** If every cell of a program is `Resolved` and
`normalize` ends with `Solved`, `Crash`, `StepLimit` or `OutOfInstructions`
without reaching a frontier, then `REFERENCE_RUN(physical(P))` gives the same
outcome, the same `steps` and the same final state. When `normalize` returns
`Loop`, the reference run either returns `STUCK` or never terminates. This
lemma is checked by the T-DIFF test.

---

## 6. Stack

### 6.1 Representation and arena

The current frame (`M.current`) lives inside `Machine` and its `pc` advances
with every instruction, without touching the arena. The `pc` of a suspended
frame **never changes while it is suspended**, so suspended frames are stored
in the arena as a persistent linked list:

```rust
struct StackNode {
    frame: Frame,
    parent: Option<NodeId>,
    depth: u16,      // number of frames in the chain (≤ 20000)
    hash: u128,      // mix(parent.hash (0 if none), frame.f, frame.pc)
}
type NodeId = u32;   // index into StackArena

stack_hash(M) = mix(hash(M.callers), M.current.f, M.current.pc)     # O(1)
```

- **Arena:** `Vec<StackNode>`. Nodes are never modified.
- **Rewinding:** the search is depth-first, so allocation follows a stack
  discipline. For each child branch, `mark = arena.mark()` is taken **before
  the candidate is applied** (END repair also creates nodes), and
  `arena.truncate(mark)` is called when the branch returns. Nodes referenced
  by the parent's state were created before the mark and are unaffected.
- A cache entry does not copy the stack; it stores a single `NodeId`. So each
  entry costs O(1) memory even with deep recursion.

### 6.2 Operations

```text
call(P, M, g):                                                   # S-CALL
    # M.current.pc already points just past the call instruction
    if exhausted(M.current.f, M.current.pc):   # R-TAIL: caller has definitely nothing left
        M.current = (g, 0)                     # replace, arena untouched
    else:
        M.callers = arena.push(M.current, parent = M.callers)   # suspend
        M.current = (g, 0)

pop(M):                                                          # S-POP
    if M.callers is None: M.current = None
    else:
        node = arena[M.callers]
        M.current = node.frame
        M.callers = node.parent
```

All three are O(1). A caller whose remainder still contains an undecided slot
(the function is not closed) is suspended; that slot may later become an
instruction.

**Difference from the engine, and why it is equivalent.** For R-TAIL the
engine asks "are all remaining physical slots `null`?". We ask
`exhausted(...)`. If the caller's remainder still contains an undecided
slot, we keep the frame; the engine would drop it if that slot later turned
out to be `null`. This difference does not change behavior (see the R-TAIL
note); it only changes how the stack is represented. The rule in §6.3
restores the canonical representation.

### 6.3 Canonical stack (INV-STACK)

**INV-STACK:** No suspended frame is `exhausted`. The current frame may be
exhausted; it is then popped at the top of the loop.

**Lemma L5.** INV-STACK holds throughout a single `normalize` call. A frame is
only suspended if it is not exhausted (S-CALL), and whether a frame is
exhausted depends only on the program. `normalize` does not change the
program, so a suspended frame cannot become exhausted later in the same call.

**Lemma L6.** Among the decision types, only **END** can break INV-STACK:

| Decision | Effect on suspended frames |
|---|---|
| Add a `Resolved` or `CondOnly` cell (`len` +1) | Adds an instruction for frames whose remainder was undecided. Even if the function becomes full, suspended frames have `pc ≤ old len`, and there is now an instruction there. Creates no exhausted frame. |
| Resolve a `NeedAction` | The cell already existed. No effect. |
| **END (`f`, `k`)** | Suspended frames with `(f, pc == k)` become exhausted. |

**S-REBUILD:** END is decided at an `OpenSlot{f, k}` frontier. At that moment
the **current frame itself** is `(f, k)`; END is decided for its own slot.
After the decision, on **that child branch's** state copy only:

```text
frames = collect the M.callers chain, bottom to top
frames = [fr for fr in frames if !(fr.f == f and fr.pc == k)]
M.callers = push frames onto the arena again, in order   # parent, depth, hash recomputed
```

The current `(f, k)` frame is not part of the repair: it is popped as
exhausted at the top of the normalize loop. This costs O(depth), paid once
per END decision rather than once per call.

**Reachable example** (`t_rebuild_middle`): function `B` calls itself through
`C`. The stack, bottom to top:

```text
B@k (suspended),  C@j (suspended),  B@k (current, OpenSlot{B, k})
```

After the decision `B[k] = END`, the current `B@k` pops, `C@j` becomes the
current frame, and the lower `B@k` is removed by the repair. Result:
`[C@j (current)]`.

---

## 7. Loop detection

### 7.1 Rule

After a `Call` completes (after S-CALL), compute the machine's **loop key**:

```text
key(M) = (pos, dir, stars, colors, callers chain, current)     # steps NOT included
```

If the key has been seen before, the outcome is `Dead(Loop)`.

**Why only at calls?** Any stretch of execution without a call is finite:
functions have finite length and nothing jumps to a slot index. An infinite
execution must contain infinitely many calls, so a repeating state also
repeats at a call point.

**Lemma L7 (soundness).** If `S → … → S` is observed under the same program,
execution is deterministic, so this path repeats forever. Each repetition
consumes steps and the star count never changes (it is part of the key), so
this branch can never become `Solved`.

### 7.2 Cache lifetime

A new `CycleDetector` is **created on every `normalize` call**: in v1 a fresh
cache is opened after every synthesis decision.

*Rationale (to be copied into the code as-is):* A path-scoped cycle cache can
safely survive synthesis decisions on the same DFS ancestry, because program
cells are monotonically refined and a completed repeated execution path only
depends on cells already fixed along that ancestry. V1 deliberately resets
cycle detection at each normalization frontier for implementation
simplicity; the cost is that a loop is detected at most one iteration later.
**Cache entries must never be shared across sibling branches.**

### 7.3 Hashing and exact equality

- `phys_hash`: Zobrist hashing. `u128` tables generated by a fixed-seed
  `splitmix64`: `ROBOT[tile][dir]`, `STAR[tile]`, `COLOR[tile][color]`.
  Moving, turning, painting and collecting a star update the hash in O(1)
  with XOR.
- `key_hash = mix(phys_hash, stack_hash(M))`.
- `CycleDetector { buckets: HashMap<u128, Vec<CycleSnapshot>> }`, where
  `CycleSnapshot = { pos, dir, stars, colors, current, callers }`. Because
  `stars` and `colors` are packed, an entry is about 120 bytes; the stack is
  not copied.
- On a hash match, **exact equality** is checked. The stack comparison walks
  both chains together: if the `NodeId`s are equal, the rest of the chains
  are certainly identical (nodes are immutable), stop. If the `depth`s
  differ, the stacks differ, stop. Otherwise compare the frames and move up
  one node. Different `NodeId`s can still hold the same contents: the same
  stack can be recreated by END repair or by a different push sequence.

**Why exact equality is mandatory:** a hash collision would cause a wrong
*prune*, i.e. a solution that exists would be missed. The check in
`finalize` (§9.3) cannot catch this: it only verifies that the solution that
*was* found works, and cannot see the branches that were cut.
Completeness depends on exact equality.

---

## 8. Candidate generation

Candidate generation has two separate steps, kept separate in the code:

- **Generator:** which cells are semantically possible?
- **Canonicalizer:** which of them are redundant copies of an equivalent
  already in the search space? (§8.5)

The one exception is P-SYM (§8.4): symmetry is generated directly as the set
of callable functions (`callable`) rather than applied as a filter, because
that is cheaper.

### 8.1 Frontier kinds and cost

| Frontier | Candidates | Cost |
|---|---|---|
| `OpenSlot{f, pc}` | `END` | +0 |
| | `Resolved{cond ∈ active conditions, action}` | +1 |
| | `CondOnly{c}` for each deferred condition `c` | +1 |
| `NeedAction{f, pc, c}` | replace with `Resolved{Is(c), action}` | +0 |

Candidates with `used + cost > budget` are not generated. At an `OpenSlot`
with the budget exhausted, only `END` remains.

- **P-STEPCUT:** if `M.steps == MAX_STEPS`:
  - `NeedAction` → `NotFound` without opening any branch.
  - `OpenSlot` → only `END` is generated.

  (*Proof:* the next non-empty cell evaluated would be step
  `MAX_STEPS + 1`, and by R-STEP it dies with `StepLimit`. `END` consumes no
  step and ends the current frame; the execution that returns dies only if
  it reaches another non-empty cell, so `END` may survive.)

### 8.2 Conditions (P-COLOR)

`cur = M.colors[M.pos]`, `PC = possible_colors`.

- `|PC| == 1`: the only active condition is `Any`; no `CondOnly` is
  generated. (*Proof:* with a single color, `Is(c)` and `Any` always behave
  the same. The canonical representation at equal cost is `Any`.)
- `|PC| ≥ 2`: active conditions are `{Any, Is(cur)}`; deferred conditions
  are `{c ∈ PC : c ≠ cur}`. (*Proof:* a color outside `PC` can never occur,
  so a cell conditioned on it never runs. Removing it lowers the cost, so it
  cannot appear in a minimal solution.)

`Any` and `Is(cur)` are not merged: they behave the same right now, but the
slot may run again later on a different color.

If `config.lazy_conditions == false`, then for each deferred `c`, every
`Resolved{Is(c), action}` cell is generated directly (eagerly) instead of
`CondOnly{c}` (§8.7). These cells are skipped for now; their actions matter
when they fire later.

### 8.3 Actions

Candidate actions for a cell with condition `cond` (`Is(c)` for `NeedAction`):

```text
Forward, TurnLeft, TurnRight,
Paint(x)  for x in allowed_paints,
Call(g)   for g in callable(state)                   (§8.4)
```

Filters:

- **P-PAINT:** if `cond == Is(x)`, `Paint(x)` is not generated. (*Proof:* the
  instruction only runs when the tile is already `x`, so it never has an
  effect. Removing it lowers the cost and the step count.) `Any: Paint(cur)`
  is generated, because it may run later on a different color and matter.
- **P-DISABLED:** a function with `cap[g] == 0` is never called. (*Proof:*
  in the engine such a call has no effect but counts as a step,
  R-RUN (232).)

### 8.4 Function symmetry (P-SYM)

- `introduced`: `g` is added the moment a `Resolved{…, Call(g)}` cell is
  **created** in the program, whether at an `OpenSlot` or when resolving a
  `NeedAction`. `CondOnly` does not introduce a function. `F1` counts as
  introduced from the start (`introduced = 0b00001`).
- Capacity classes: among `F2..F5`, functions with `cap > 0` are grouped by
  capacity. `F1` is in no class: as the entry point it cannot be swapped with
  the others.
- `callable(state) = introduced ∪ { the lowest-index not-yet-introduced function of each class }`.

Examples:
- `cap = [6, 6, 0, 6, 0]` (catalog puzzle #2973): initially `{F1, F2}`; once
  `F2` is introduced, `F4` becomes callable too.
- `cap = [7, 4, 2, 4, 2]`: classes `4 → [F2, F4]`, `2 → [F3, F5]`.
  Initially `{F1, F2, F3}`.

*Proof:* swapping the names of two functions with the same capacity (and all
calls to them) gives a valid program with the same cost, and execution is
unchanged. In any solution, each class can be renamed in the order in which
its functions are first introduced. That order is determined by execution
itself, so the renamed program satisfies this rule and the search finds it.
This does **not** hold across different capacities: a 4-slot body may not
fit into a 2-slot function.

### 8.5 Local equivalence pruning (canonicalizer)

After a cell is placed or resolved at index `i`, `is_locally_canonical(fn, i)`
is called; it only looks at the windows containing `i`: `[i-2, i+2]`. At a
`NeedAction`, cells to the right may already be filled, so both directions
are checked.

- **P-TURN:** For consecutive `Resolved` turn cells in the same function with
  the **same condition**, these patterns are forbidden:
  - `L R` and `R L`: together they do nothing and are removed.
  - `L L L` and `R R R`: equivalent to a single `R` and a single `L`,
    respectively.
  - `R R`: equivalent to `L L` (180°). The canonical form is `L L`.

  So a run of same-condition turns can only be `L`, `R` or `L L`.

  *Proof:* functions are only entered at their start, so cell `i+1` is always
  evaluated right after cell `i`. A turn does not change the tile color. So
  two consecutive turns with the same condition either both run or both are
  skipped. The rewritten form produces the same state at lower or equal cost
  and with fewer or equal steps; fewer steps cannot break the 20000 limit.

  `CondOnly` cells do not count as turns. They are checked when they are
  resolved, at the `NeedAction`.
- **P-EMPTYFN:** `END` is not generated when `pc == 0`. (*Proof:* for `F1`
  that program does nothing. For `g ≠ F1`, every call to a function with an
  empty body has no effect but uses a slot. Removing those calls lowers the
  cost.)

### 8.6 Ordering (non-normative)

Ordering does not affect correctness; it only affects how quickly the final
budget iteration reaches a solution. The failing budget iterations
`1..K-1` are always searched exhaustively. A fixed order is enough for v1:

```text
OpenSlot:   Any:Forward, cur:Forward, Any:Call(introduced), Any:TurnLeft, Any:TurnRight,
            cur:(same order), Any:Call(new), Paint…, CondOnly…, END
NeedAction: Forward, Call(introduced), TurnLeft, TurnRight, Call(new), Paint…
```

### 8.7 `Config`: ablation flags

```rust
struct Config {
    lazy_conditions:   bool,   // CondOnly / NeedAction (§8.2)
    function_symmetry: bool,   // P-SYM (§8.4)
    peephole:          bool,   // P-TURN, P-PAINT, P-EMPTYFN (§8.3, §8.5)
    cycle_detection:   bool,   // §7
    step_cut:          bool,   // P-STEPCUT (§8.1)
}   // default: all true
```

**Rule:** turning a flag off removes the optimization and makes the search
space bigger; **it never forbids a branch**. Every `Config` must find the
same minimal cost (`t_config_equivalence`).

| When the flag is `false` | Behavior |
|---|---|
| `lazy_conditions` | Instead of `CondOnly{c}`, every `Resolved{Is(c), action}` cell is generated for each deferred `c` (eager). `NeedAction` never occurs. This means **expanding** these cells up front, not **forbidding** them; forbidding them would lose solutions. |
| `function_symmetry` | `callable` = every function with `cap > 0`. |
| `peephole` | P-TURN, P-PAINT and P-EMPTYFN are not applied. |
| `cycle_detection` | Loops die with `StepLimit` (slow but correct). |
| `step_cut` | Candidate generation continues as usual; branches die with `StepLimit` on the next step. |

P-COLOR, P-DISABLED and P-CONN cannot be turned off by a flag. They define
the representation itself (a color that cannot exist, a function that does
not exist, a star that cannot be reached).

---

## 9. Search

### 9.1 Outer loop: iterative deepening on budget (IDDFS)

```text
solve(level, config, limits):
    if P-CONN fails: return Unsolvable(Disconnected)
    for budget in 0 ..= sum(cap):
        root = SearchState {
            program: empty (all functions open, len = 0, ended = false),
            machine: initial state, current = (F1, 0), callers = None, steps = 0,
            used: 0, introduced: {F1},
        }
        arena.clear()
        match search(root, budget):
            Found(s)  → return Solved(finalize(s))
            Timeout   → return Timeout
            NotFound  → continue
    return Unsolvable(Exhausted)    # no solution at any budget (under engine semantics)
```

The `budget = 0` iteration solves star-less puzzles with the empty program.
For a puzzle with stars it ends immediately because of P-EMPTYFN.

### 9.2 Inner loop: DFS

```text
search(self, s: SearchState, budget) -> Result<Option<SearchState>, Timeout>:
    self.limits.check()?                             # time and node limits
    self.stats.search_nodes += 1
    let mut s = s
    let mut cycles = CycleDetector::new()            # §7.2
    match normalize(self, &mut s, &mut cycles):
        Solved         → return Ok(Some(s))
        Dead(reason)   → self.stats.dead(reason); return Ok(None)
        OpenSlot{f,pc} →
            for cand in self.open_candidates(&s, f, pc, budget):   # §8, ordered and filtered
                mark = self.arena.mark()             # BEFORE the candidate (END repair allocates nodes)
                child = s                            # Copy
                apply(&mut child, cand)              # cells[len] = …, len += 1  |  ended = true
                if cand == END: S-REBUILD(self.arena, &mut child.machine, f, pc)
                r = self.search(child, budget)
                self.arena.truncate(mark)
                if r? is Some: return r
            return Ok(None)
        NeedAction{f,pc,c} →
            if P-STEPCUT applies: return Ok(None)
            for act in self.need_candidates(&s, f, pc, c):
                mark = self.arena.mark()
                child = s
                child.program.fns[f].cells[pc] = Resolved{Is(c), act}
                if act == Call(g): child.introduced |= bit(g)
                r = self.search(child, budget)
                self.arena.truncate(mark)
                if r? is Some: return r
            return Ok(None)
```

When `apply` adds a `Call(g)` cell it does `introduced |= bit(g)` and
`used += 1`; when it adds a `CondOnly` it only does `used += 1`.

### 9.3 `finalize`

```text
finalize(s):
    assert (INV-FIN) all cells are Resolved       # debug_assert
    physical = for each f: cells[..len] ++ null * (cap[f] - len)
    r = REFERENCE_RUN(physical)
    assert r == SUCCESS                            # always, release builds too
    return Solution { physical, cost: s.used, steps: r.steps }
```

**INV-FIN:** No `CondOnly` cell can remain in the first solution found.
(*Proof:* a `CondOnly` that never fired was skipped every time it was
reached. Removing it keeps the behavior and lowers both the step count and
the cost by 1. Then a solution would exist at `budget - 1`, but that
iteration already failed. Contradiction.) If this assert ever fires, there is
a bug.

Function tails left undecided become `null` in the output. They are never
reached, so they have no effect and do not count toward the cost.

This two-interpreter setup (`normalize` for searching, `REFERENCE_RUN` for
verifying) is the solver's safety belt: even if `normalize` has a bug, a
wrong solution cannot get out.

### 9.4 `SearchStats`

Reported per puzzle, summed over all budget iterations. Lives in `Solver`,
**not** in `SearchState`.

| Counter | Incremented when |
|---|---|
| `search_nodes` | On every `search` call. Also reported per budget (`nodes_per_budget`). |
| `normalize_calls` | On every `normalize` call. |
| `instructions_evaluated` | On every `consume_step` call. **As important as the node count**: if an optimization cuts nodes but increases normalize work, wall-clock time does not drop as much as expected. |
| `open_frontiers`, `need_action_frontiers` | When the corresponding frontier is returned. |
| `candidates_generated`, `candidates_searched` | Candidates produced, and candidates actually recursed into. |
| `dead_crash`, `dead_step_limit`, `dead_out_of_instructions`, `dead_loop` | When `normalize` dies for that reason. |
| `prune_budget`, `prune_step_cut`, `prune_symmetry`, `prune_peephole` | When that rule eliminates a candidate. |
| `ends_selected`, `condonly_created`, `condonly_resolved` | When that decision is applied. |
| `stack_pushes`, `tail_calls`, `returns`, `stack_rebuilds`, `stack_nodes_rebuilt` | On stack operations. |
| `max_search_depth`, `max_call_depth` | Maximum observed value. |

---

## 10. Correctness summary

**Soundness.** Every returned program succeeds in the engine: by L1–L5,
`normalize` simulates the engine exactly, and on top of that every solution
is re-checked with `REFERENCE_RUN` (§9.3) and with the Dart engine (§12).

**Completeness and optimality.** If a solution of cost `K` exists,
`search(budget = K)` finds a solution of cost `K` (assuming no time limit;
for every `Config`). *Proof sketch:* take a minimal solution `Q`. Left-pack it
(L1), rename its functions (P-SYM), and apply the P-TURN, P-COLOR and P-PAINT
rewrites. None of these rewrites increases cost, and all preserve behavior.
The search then follows `Q`'s cells:

- At each `OpenSlot`, `Q`'s cell at that slot is either a candidate with an
  active condition, a `CondOnly` candidate with a deferred condition (its
  action is chosen later at a `NeedAction`; with `lazy_conditions` off it is
  a candidate directly), or `null`, which corresponds to the `END`
  candidate.
- P-EMPTYFN, P-STEPCUT and INV-FIN are consistent with `Q` being minimal and
  successful.
- L7 does not cut `Q`'s path: `Q` reaches success, so its execution has no
  repeating state.

Budgets `0..K-1` are searched exhaustively, so the first solution found is
minimal.

---

## 11. Test plan

| Test | What it locks down |
|---|---|
| `t_level_*` | The catalog loads; puzzles that exceed the limits, have ragged rows or start on a gap return `Unsupported` and do not panic. |
| `t_ref_*` | `REFERENCE_RUN` matches Dart on the tutorial puzzles (the programs in `test/tutorial_levels_test.dart`). |
| `t_step_limit_boundary` | Build the state directly: at `steps = 19999`, a `Forward` that collects the last star → `Solved`, `steps = 20000`. At `steps = 20000`, the same instruction → `Dead(StepLimit)`, the robot has not moved, the star is still there. The same test is repeated for a condition-mismatched instruction and for a skipped `CondOnly`. |
| `t_frontier_no_step` | When `OpenSlot` or a matching `NeedAction` is returned, `pc` and `steps` are unchanged. |
| `t_tail_call`, `t_non_tail_call` | R-TAIL: `F1: [Forward, Call F1]` adds no node to the arena. A call with a continuation suspends the caller. |
| `t_diff_random` | **T-DIFF:** random fully-filled physical programs (fixed seed, ≥ 10⁵ of them) run on catalog puzzles through both `REFERENCE_RUN` and `normalize`. Outcome, `steps` and final state must match (L4). |
| `t_loop_*` | A tail-recursive loop is caught as `Dead(Loop)`. Deep non-tail recursion is not wrongly pruned and ends in `Dead(StepLimit)`. A "loop" that collects a star is not a loop. |
| `t_cycle_exact_equality` | Two different states with the same hash (forced by hand) are not treated as a loop. |
| `t_rebuild_middle` | The reachable example in §6.3: after END, `[C@j]` remains, with the hash chain and `depth` recomputed. |
| `t_zobrist_*` | Painting and collecting a star change `phys_hash`; painting back restores the old hash. |
| `t_p_sym`, `t_p_turn`, `t_p_paint`, `t_p_color`, `t_p_emptyfn`, `t_p_stepcut` | Each pruning rule, with both positive and negative examples. `t_p_sym` also checks that functions of different capacity are not merged. |
| `t_p_turn_needaction` | With `Red:?, Red:R`, `L` is not generated for `?`. |
| `t_e2e_tutorials` | The tutorial puzzles are solved at their expected minimal costs. |
| `t_e2e_bruteforce` | On small hand-built puzzles (total capacity ≤ 4), the solver finds the same minimal cost as a naive brute force that tries every physical program. **The real optimality test.** |
| `t_config_equivalence` | On a small puzzle set, every `Config` combination finds the same minimal cost. |
| Dart: `solver_solutions_test.dart` | §12. |

---

## 12. Output format and Dart verification

`solutions.json`:

```json
{
  "solver": "robozzle-solver 0.1.0",
  "maxSteps": 20000,
  "config": { "lazyConditions": true, "functionSymmetry": true, "peephole": true, "cycleDetection": true, "stepCut": true },
  "results": [
    {
      "sourceId": 195,
      "status": "solved",
      "cost": 7,
      "steps": 1234,
      "program": [
        ["forward", "red:turnLeft", "callF2", null, null, null, null],
        ["forward", "blue:callF1", null, null],
        [null, null, null, null],
        [],
        []
      ],
      "stats": { "millis": 12, "searchNodes": 45678, "instructionsEvaluated": 912345, "nodesPerBudget": [1, 1, 5, 40] }
    },
    { "sourceId": 53, "status": "timeout", "stats": { "millis": 60000, "searchNodes": 123456789 } },
    { "sourceId": 999, "status": "unsupported", "reason": "function capacity 13 exceeds 12" }
  ]
}
```

- Each function array has length `cap[f]`; empty slots are `null`.
- Instruction syntax: `"<condition>:<action>"`. When the condition is `Any`,
  the condition part is omitted. Condition names are `red | green | blue`;
  action names are exactly Dart's `ActionType` names: `forward`, `turnLeft`,
  `turnRight`, `paintRed`, `paintGreen`, `paintBlue`, `callF1` … `callF5`. So
  the Dart side can parse them directly with `ActionType.values.byName(...)`.
- `status` values: `solved | timeout | unsolvable | unsupported`.
- The `stats` fields are the camelCase form of the counters in §9.4.

**Dart test** (`test/solver_solutions_test.dart`): reads the catalog and
`solutions.json` with `dart:io`. For each `solved` entry, it builds the
program as a `RobotProgram` and runs it with `runToCompletion()`.
Expectations:

- `status == RunStatus.success`
- `interpreter.stepsExecuted == the entry's steps`. An exact step-count
  match is the strongest evidence that the two semantics really agree.

If `solutions.json` does not exist, the test is skipped.

---

## 13. CLI

```text
solver <catalog.json> [--id <sourceId>]... [--all]
       [--timeout-ms <ms>]   (per puzzle, default 10000)
       [--node-limit <n>]
       [--out <solutions.json>]
       [--no-lazy-conditions] [--no-function-symmetry] [--no-peephole]
       [--no-cycle-detection] [--no-step-cut]
```

One progress line per puzzle; at the end, a summary by difficulty: puzzles
solved, average time, total `search_nodes` and `instructions_evaluated`.

Parallelism: none in v1. v1.5 adds parallelism across puzzles (`rayon`),
which is easy and safe because puzzles are independent (each thread uses its
own `Solver`).

---

## 14. Module layout and implementation order

The module list, dependencies and implementation order are now defined in
[`SPEC.md`](SPEC.md), Appendix B. In short: `types.rs`, `puzzle.rs`,
`program.rs`, `machine.rs`, `stack.rs`, `reference.rs`, `normalize.rs`,
`canonical.rs`, `search.rs`, `stats.rs`, `lib.rs`, `main.rs`.

The reasoning behind the order is unchanged: the oracle first
(`reference.rs`), then `normalize` (checked by T-DIFF), then the simplest
search (eager conditions), and then one optimization per step, each with
its effect recorded in `BENCHMARKS.md`.

---

## 15. Out of scope for v1 (to be decided after measuring)

- **Undo/trail (make/unmake).** Rationale in §4.0. Revisited if
  `SearchStats` shows copying to be a real bottleneck.
- **Global transposition table.** Rationale: a partial program is reached by
  exactly one path in the search tree, so the table would get no hits.
- **Path-scoped loop cache** (§7.2).
- **`function_mask_below`:** storing "does this chain contain function `f`?"
  on arena nodes, to skip S-REBUILD when it is not needed.
- Statistics-based ordering (killer/history), an `--any` mode (any solution
  rather than the shortest).
- Parallel search within a single puzzle.
- Pushdown analysis for non-tail recursion.
- Secondary objective: fewest steps at equal cost.

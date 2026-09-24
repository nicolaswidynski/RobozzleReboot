# Robozzle Solver — Tasarım Spesifikasyonu (v1)

> **Dil / Language:** Türkçe metin aşağıda. The English version follows the
> Turkish one: [jump to English](#english). Both versions describe the same
> spec with the same section numbers and rule IDs; if they ever disagree, fix
> both in the same change.

Bu belge solver'ın **ne yapacağını ve neden doğru olduğunu** tanımlar. Kod bu
belgeye göre yazılır; bir kural değişirse önce burası güncellenir.

Kimlik etiketleri (`R-*`, `INV-*`, `P-*`, `T-*`) koddaki yorumlarda ve test
isimlerinde referans olarak kullanılır. Örneğin bir budama kuralının kodu
`// P-TURN` yorumu taşır, testi `t_p_turn_*` diye adlandırılır.

---

## 0. Amaç ve temel ilkeler

**Amaç:** `assets/levels_catalog.json` içindeki her bulmaca için, uygulamanın
motorunda ([`lib/engine/interpreter.dart`](../lib/engine/interpreter.dart))
başarıyla çalışan ve **dolu slot sayısı en az olan** programı bulmak.

- **Birincil hedef:** dolu (non-empty) slot sayısını en aza indirmek.
- **Kısıt:** gerçek motordaki 20000 adım sınırı. Bu bir hedef değil, bir kısıttır.
- **İkincil hedef (v1'de yok):** aynı slot sayısında daha az adım.

Üç ilke her kararın üstündedir:

1. **Motor semantiği kutsaldır.** Solver'ın "çözüm" dediği her program Dart
   motorunda `RunStatus.success` vermek ZORUNDADIR (§2, §10).
2. **Budama yalnızca kanıtla yapılır.** Bir dal ancak içinde en küçük bir
   çözüm olamayacağı *ispatlanabiliyorsa* kesilir. "Kötü görünüyor" bir budama
   sebebi değildir; sezgisel (heuristic) bilgi yalnızca dalların *sırasını*
   belirler (§8.6).
3. **Belirlenimcilik.** Aynı girdi her zaman aynı çıktıyı verir. Arama
   kararları hiçbir zaman `HashMap` iterasyon sırasına bağlı olmaz.

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
- Stack derinliğinin sınırı yoktur. Solver da bir sınır **koymaz**.
- Yıldız yalnızca bir kareye **girerken** alınır. Katalogda başlangıç karesinde
  yıldız olan bulmaca yok; olsaydı bile, o yıldız robot o kareye tekrar
  girmeden alınmış sayılmazdı.

---

## 3. Girdi ve ön işleme

### 3.1 Katalog

Her kayıt: `sourceId`, `rows` (string listesi), `startRow`, `startCol`,
`startDirection` (`up|right|down|left`), `slotsPerFunction` (5 sayı),
`allowedCommands` (boya bitmask'ı: `1` = kırmızı, `2` = yeşil, `4` = mavi).

Karakterler: `' '` ya da `'.'` boşluk; `r g b` renkli kare; `R G B` aynı
renkte, üzerinde yıldız olan kare.

Katalog üzerinde doğrulanmış varsayımlar (loader bunları `assert` eder):
satırların hepsi aynı uzunlukta; grid en fazla 12×16 (192 kare); başlangıç
karesi hiçbir zaman boşluk değil; `cap[F1] > 0`; her bulmacada en az 1 yıldız
var; `cap[f] ≤ 10`; toplam kapasite ≤ 50.

### 3.2 Hazırlanan statik veri (`Level`)

| Alan | Tanım |
|---|---|
| `TileId` | `row * cols + col`, `u8` (≤ 191). Boşluklar da bir `TileId` alır ama `is_tile = false`. |
| `neighbor[tile][dir]` | `Option<TileId>`. Grid dışı ya da boşluk ise `None`. |
| `init_color[tile]` | Karenin başlangıç rengi. |
| `init_stars` | Yıldızlı karelerin kümesi, `[u64; 3]` bitset. |
| `allowed_paints` | `allowedCommands` bitmask'ından türetilen renk kümesi. |
| `possible_colors` | `{başlangıçta griddeki renkler} ∪ allowed_paints` (§8.2). |
| `cap[0..5]` | Fonksiyon kapasiteleri. |
| `class_rep` | F2..F5 için kapasite sınıfları (§8.4). |

Yön kodlaması: `Up = 0, Right = 1, Down = 2, Left = 3`.
`turn_left(d) = (d + 3) % 4`, `turn_right(d) = (d + 1) % 4`.

### 3.3 Statik kontroller

- **P-CONN:** Başlangıç karesinden BFS ile gidilebilen karelerin dışında
  yıldız varsa bulmaca `Unsolvable(Disconnected)` döner ve arama hiç başlamaz.
  Grid'in şekli boyamayla değişmediği için bu kontrol bir kez yapılır.

---

## 4. Veri yapıları

### 4.1 Komutlar

```rust
enum Color { Red, Green, Blue }
enum Cond  { Any, Is(Color) }
enum Action { Forward, TurnLeft, TurnRight, Paint(Color), Call(FnId) }
```

### 4.2 Kısmi program

```rust
enum Cell {
    Resolved { cond: Cond, action: Action },
    CondOnly { cond: Color },          // koşul seçildi, aksiyon henüz yok
}

struct FunctionDraft {
    cells: Vec<Cell>,   // karar verilmiş hücreler, soldan sıkıştırılmış
    ended: bool,        // true: cells'ten sonrası kesin olarak boş (END)
}

struct PartialProgram {
    fns: [FunctionDraft; 5],
    introduced: u8,     // bitmask: çağrı hücresi oluşturulmuş fonksiyonlar (§8.4)
    used: u8,           // maliyet: Resolved ve CondOnly hücrelerin toplamı
}
```

Tanımlar:

- `len(f) = fns[f].cells.len()`.
- **Kapalı fonksiyon:** `closed(f) := fns[f].ended || len(f) == cap[f]`.
- **Tükenmiş frame:** `exhausted(f, pc) := pc == len(f) && closed(f)`. Bu frame'in
  önünde kesin olarak çalışacak hiçbir komut yoktur.
- Fiziksel karşılık: `physical(f) = cells (hepsi Resolved) ++ [null; cap[f] - len(f)]`.

**Lemma L1 (sola sıkıştırma).** Bir fonksiyondaki `null` slotları sona taşımak
davranışı değiştirmez. `null` adım saymaz ve atlanır (R-NULL). R-TAIL yalnızca
"sonrasında dolu slot var mı?" sorusuna bakar ve bunun cevabı taşımayla
değişmez. Fonksiyonlara yalnızca başlarından girilir, slot indeksine atlayan
bir komut yoktur. Dolayısıyla her fiziksel programın aynı davranışa ve aynı
maliyete sahip tek bir sola sıkıştırılmış hali vardır, ve yalnızca bu halleri
aramak hiçbir çözümü kaybettirmez.

### 4.3 Makine

```rust
struct Machine {
    pos: TileId,
    dir: u8,
    colors: [Color; 192],   // v1 için basit dizi
    stars: [u64; 3],
    star_count: u16,
    steps: u32,
    top: Option<Frame>,     // çalışan frame (pc'si değişir)
    rest: StackRef,         // askıdaki frame'ler, kalıcı stack (§6)
    phys_hash: u128,        // pos, dir, stars, colors Zobrist hash'i (§7.3)
}

struct Frame { f: u8, pc: u8 }
```

Makine bir frontier'da klonlanır. Boyutu yaklaşık 250 bayt olduğu için
kopyalamak ucuzdur; v1'de make/unmake (değişikliği yapıp geri alma) yapılmaz.

---

## 5. `normalize()`: çalıştırma katmanı

`normalize(P, M, seen) -> Outcome` kısmi program `P` altında makineyi `M`
**yerinde** ilerletir. Program sabittir; bu fonksiyon hiçbir karar vermez.

```rust
enum Outcome {
    Solved,
    Dead(DeadReason),                   // Crash | StepLimit | OutOfInstructions | Loop
    OpenSlot   { f: u8, pc: u8 },       // pc == len(f), fonksiyon kapalı değil
    NeedAction { f: u8, pc: u8, cond: Color },
}
```

```text
normalize(P, M, seen):                                          # N-*
    loop:
        if M.star_count == 0: return Solved                     # N-SOLVED
        if M.top is None:     return Dead(OutOfInstructions)
        (f, pc) = M.top

        if pc == len(f):                                        # N-END
            if closed(f): pop(M); continue                      # R-POP ile aynı
            return OpenSlot{f, pc}                              # ADIM SAYILMAZ, pc İLERLEMEZ

        match P.fns[f].cells[pc]:

            CondOnly{c}:                                        # N-CONDONLY
                if M.colors[M.pos] == c:
                    return NeedAction{f, pc, c}                 # ADIM SAYILMAZ, pc İLERLEMEZ
                if !consume_step(M): return Dead(StepLimit)
                M.top.pc += 1
                continue                                        # koşul tutmadı, atla

            Resolved{cond, action}:                             # N-RESOLVED
                if !consume_step(M): return Dead(StepLimit)     # R-STEP: ÖNCE sınır
                M.top.pc += 1
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
                        if seen.check_and_insert(M):            # §7
                            return Dead(Loop)

consume_step(M):
    M.steps += 1
    return M.steps <= MAX_STEPS
```

Hücreler hiçbir zaman `cap[g] == 0` olan bir fonksiyonu çağırmaz (§8.3), bu
yüzden R-RUN'daki (232) dalının karşılığına gerek yoktur.

**Lemma L2 (frontier'da durmak).** `OpenSlot` ve `NeedAction` durumunda makine,
o slot değerlendirilmeden **hemen önceki** state'tedir: adım sayılmamış, `pc`
ilerlememiştir. Karar verildikten sonra `normalize` aynı slotu motorun yaptığı
gibi baştan işler. Böylece her dolu slot tam olarak bir kez sayılır.

**Lemma L3 (frontier'dan devam).** Frontier'a kadar olan çalışma, karar
verilecek hücreyi hiç okumamıştır; okusaydı orada dururdu. Bu yüzden her çocuk
dal, frontier makinesinin bir kopyasından devam edebilir. Baştan çalıştırmaya
gerek yoktur.

**Lemma L4 (eşdeğerlik).** Bir `P` programının bütün hücreleri `Resolved` ise
ve `normalize` hiç frontier'a varmadan `Solved`, `Crash`, `StepLimit` ya da
`OutOfInstructions` ile bitiyorsa, `REFERENCE_RUN(physical(P))` aynı sonucu,
aynı `steps` değerini ve aynı son state'i verir. `Loop` sonucunda ise
referans çalıştırma ya `STUCK` verir ya da hiç sonlanmaz. Bu lemma T-DIFF
testiyle doğrulanır.

---

## 6. Stack

### 6.1 Temsil

Çalışan frame (`M.top`) değiştirilebilir durumdadır ve onun `pc`'si her komutta
ilerler. Askıdaki frame'lerin `pc`'si ise **askıdayken değişmez**, bu yüzden
kalıcı (persistent) bir bağlı liste içinde tutulurlar:

```rust
struct StackNode { frame: Frame, parent: StackRef, depth: u32, hash: u128 }
type StackRef = Option<NodeId>;          // NodeId = arena içindeki u32 indeks

node.hash = mix(parent.hash (yoksa 0), frame.f, frame.pc)
stack_hash(M) = mix(hash(M.rest), M.top.f, M.top.pc)
```

- **Arena:** `Vec<StackNode>`. Arama derinlik öncelikli (DFS) olduğu için yer
  açma da yığın disipliniyle yapılır: bir çocuk daldan dönülünce
  `arena.truncate(mark)`. O dalın oluşturduğu düğümlere artık kimse referans
  vermez.
- Cache kaydı stack'i kopyalamaz, sadece `NodeId` tutar. Böylece derin
  özyinelemede bile kayıt başına O(1) bellek harcanır.

### 6.2 İşlemler

```text
call(P, M, g):                                                   # S-CALL
    if exhausted(M.top.f, M.top.pc):      # R-TAIL: çağıranın devamı kesin boş
        M.top = (g, 0)                    # replace
    else:
        M.rest = push_node(M.rest, M.top) # askıya al
        M.top  = (g, 0)

pop(M):                                                          # S-POP
    if M.rest is None: M.top = None
    else: M.top = node(M.rest).frame; M.rest = node(M.rest).parent
```

**Motordan fark ve eşdeğerlik.** Motor R-TAIL'de "kalan fiziksel slotların
hepsi `null` mı?" diye sorar. Biz `exhausted(...)` diye soruyoruz. Çağıranın
kalanında bir `UNKNOWN` varsa (fonksiyon kapalı değilse) frame'i tutarız; motor
ise o slot sonradan `null` olursa frame'i silerdi. Bu fark davranışı
değiştirmez (R-TAIL notu), sadece stack'in gösterimini değiştirir. Gösterimi
düzeltmek için §6.3'teki kural uygulanır.

### 6.3 Canonical stack (INV-STACK)

**INV-STACK:** Askıdaki frame'lerin hiçbiri `exhausted` değildir. Çalışan
frame (`top`) tükenmiş olabilir; o zaman döngünün başında pop edilir.

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

**S-REBUILD:** END kararı verildikten sonra, **yalnızca o çocuk dalın** makine
kopyası üzerinde:

```text
frames = M.rest zincirini alttan üste topla
frames = [fr for fr in frames if !(fr.f == f and fr.pc == k)]
M.rest = frames'i arenaya yeniden push et (hash zinciri baştan hesaplanır)
```

Maliyeti O(derinlik), ama çağrı başına değil END kararı başına ödenir.
Frame'ler stack'in **ortasından** da silinebilir. Örnek:
`[B@k, C@j, B@k (top)]` iken B'nin k. slotuna END denirse top pop olur, C
çalışmaya devam eder, alttaki `B@k` silinir.

---

## 7. Döngü tespiti

### 7.1 Kural

Bir `Call` gerçekleştikten sonra (S-CALL bittikten sonra) makinenin **döngü
anahtarı** hesaplanır:

```text
key(M) = (pos, dir, stars, colors, [rest'teki frame'ler], top)     # steps DAHİL DEĞİL
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

`seen` **her `normalize` çağrısında sıfırdan başlar**: v1'de her sentez
kararından sonra yeni bir cache açılır.

*Gerekçe (kodda aynen yazılacak):* Bir `S` state'i bir karardan önce görülmüş
olsun ve karardan sonra tekrar görülsün. İkinci görülme anında `S → … → S`
yolunun okuduğu her hücre artık programda sabittir ve ileride eklenecek
hücreler bu yolu etkileyemez. Yani cache'i o anki arama yolu boyunca taşımak
**da** güvenli olurdu. Güvenli **olmayan** tek şey cache'i kardeş dallar
arasında paylaşmaktır. v1'de her kararda sıfırlıyoruz çünkü daha basit, ve
bedeli döngünün en fazla bir tur geç yakalanması.

### 7.3 Hash ve kesin eşitlik

- `phys_hash`: Zobrist yöntemi. Sabit tohumlu (seed) bir `splitmix64` ile
  üretilen `u128` tablolar kullanılır: `ROBOT[tile][dir]`, `STAR[tile]`,
  `COLOR[tile][color]`. Hareket, dönüş, boyama ve yıldız toplama hash'i
  XOR ile O(1) günceller.
- `key_hash = mix(phys_hash, stack_hash(M))`.
- `seen: HashMap<u128, Vec<SeenEntry>>`. Hash eşleşince **kesin
  eşitlik** kontrol edilir: `pos`, `dir`, `stars`, `colors` ve stack zinciri
  (aynı `NodeId`'ye ulaşana ya da kökte bitene kadar frame frame karşılaştırma).
  `SeenEntry` renk dizisinin bir kopyasını tutar (192 bayt).

Not: Bir hash çakışmasının sonucu yanlış bir *budama* olurdu, yani bir çözüm
kaçırılırdı; yanlış bir çözüm üretilmezdi. Yine de kesin eşitlik v1'de
zorunludur.

---

## 8. Aday üretimi

### 8.1 Frontier türleri ve maliyet

| Frontier | Adaylar | Maliyet |
|---|---|---|
| `OpenSlot{f, pc}` | `END` | +0 |
| | `Resolved{cond ∈ aktif koşullar, action}` | +1 |
| | `CondOnly{c}`, `c` ertelenen koşul | +1 |
| `NeedAction{f, pc, c}` | `Resolved{Is(c), action}` ile yer değiştirme | +0 |

`used + maliyet > budget` olan aday üretilmez. `OpenSlot`'ta bütçe dolduysa
geriye sadece `END` kalır.

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

### 8.3 Aksiyonlar

Hücrenin koşulu `cond` (`NeedAction`'da `Is(c)`) için aday aksiyonlar:

```text
Forward, TurnLeft, TurnRight,
Paint(x)  for x in allowed_paints,
Call(g)   for g in callable(P)                       (§8.4)
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
  `CondOnly` bir fonksiyonu tanıtmaz. `F1` baştan tanıtılmış sayılır.
- Kapasite sınıfları: `F2..F5` arasında `cap > 0` olanlar kapasiteye göre
  gruplanır. `F1` hiçbir sınıfa girmez, çünkü giriş noktası olduğu için
  diğerleriyle yer değiştiremez.
- `callable(P) = introduced ∪ { her sınıfta henüz tanıtılmamış en küçük indeksli fonksiyon }`.

Örnek: `cap = [6, 6, 0, 6, 0]` (katalogdaki #2973) için başta çağrılabilenler
`{F1, F2}`. `F2` tanıtıldıktan sonra `F4` de çağrılabilir hale gelir.

*Kanıt:* Aynı kapasiteli iki fonksiyonun isimleri (ve bütün çağrıları)
değiştirilirse, geçerli ve aynı maliyetli bir program elde edilir ve
çalıştırma değişmez. Bir çözümde her sınıf, fonksiyonların ilk tanıtılma
sırasına göre yeniden adlandırılabilir. Bu sıra çalıştırmanın kendisi
tarafından belirlenir, dolayısıyla yeniden adlandırılmış program bu kuralı
sağlar ve arama tarafından bulunur. Farklı kapasiteli fonksiyonlar için bu
geçerli **değildir**: 4 slotluk bir gövde 2 slotluk bir fonksiyona sığmayabilir.

### 8.5 Yerel eşdeğerlik budamaları

Hücre `i` indeksine yerleştirildikten sonra, `i`'yi içeren pencereler
kontrol edilir: `[i-2, i+2]`. `NeedAction`'da sağdaki komşular zaten dolu
olabilir, bu yüzden iki yöne de bakılır.

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
ulaşıldığını etkiler. v1'de sabit bir sıra yeterli:

```text
OpenSlot:   Any:Forward, cur:Forward, Any:Call(tanıtılmış), Any:TurnLeft, Any:TurnRight,
            cur:(aynı sıra), Any:Call(yeni), Paint…, CondOnly…, END
NeedAction: Forward, Call(tanıtılmış), TurnLeft, TurnRight, Call(yeni), Paint…
```

---

## 9. Arama

### 9.1 Dış döngü: bütçeye göre derinleştirme (IDDFS)

```text
solve(level, limits):
    if P-CONN başarısız: return Unsolvable(Disconnected)
    for budget in 1 ..= sum(cap):
        root_program = boş (bütün fonksiyonlar açık, used = 0, introduced = {F1})
        root_machine = başlangıç state'i, top = (F1, 0), rest = None
        match search(root_program, root_machine, budget):
            Found(p)  → return Solved(finalize(p))
            Timeout   → return Timeout
            NotFound  → continue
    return Unsolvable(Exhausted)    # hiçbir bütçede çözüm yok (motor semantiği altında)
```

`budget = 0` atlanır; her bulmacada en az bir yıldız olduğu için boş program
hiçbir zaman çözüm değildir.

### 9.2 İç döngü: DFS

```text
search(P, M, budget):
    limits.check()?                                  # zaman ve node sınırı → Timeout
    seen = yeni cache
    match normalize(P, &mut M, &mut seen):
        Solved         → return Found(P)
        Dead(_)        → return NotFound
        OpenSlot{f,pc} →
            for cand in open_candidates(P, M, f, pc, budget):     # §8, sıralı
                (P2, M2) = (P.clone(), M.clone())
                apply(P2, cand)                      # cells.push / ended = true
                if cand == END: S-REBUILD(M2, f, pc)
                r = search(P2, M2, budget)?
                if r is Found: return r
            return NotFound
        NeedAction{f,pc,c} →
            for act in need_candidates(P, M, f, pc, c):
                (P2, M2) = (P.clone(), M.clone())
                P2.fns[f].cells[pc] = Resolved{Is(c), act}
                r = search(P2, M2, budget)?
                if r is Found: return r
            return NotFound
```

Her `search` çağrısı bir **node** sayılır; istatistiklerde bütçe başına ayrı
ayrı raporlanır.

### 9.3 `finalize`

```text
finalize(P):
    assert (INV-FIN) bütün hücreler Resolved      # debug_assert
    physical = her f için cells ++ null * (cap[f] - len(f))
    assert REFERENCE_RUN(physical) == SUCCESS     # her zaman, release derlemede de
    return (physical, P.used, steps)
```

**INV-FIN:** İlk bulunan çözümde `CondOnly` hücre kalamaz. (*Kanıt:* Hiç
tetiklenmemiş bir `CondOnly` her seferinde atlanmıştır. Silinirse davranış
aynı kalır, sadece adım sayısı ve maliyet 1 azalır. O zaman `budget - 1`
turunda bir çözüm olurdu, ama o tur zaten başarısız oldu. Çelişki.)
Tetiklenirse bir bug var demektir.

Açık kalmış fonksiyon sonları çıktıda `null` olur. Bunlar hiçbir zaman
ulaşılmadığı için hiçbir etkileri yoktur ve maliyete sayılmazlar.

---

## 10. Doğruluk özeti

**Sağlamlık (soundness).** Döndürülen her program motorda `SUCCESS` verir:
L1–L5 gereği `normalize` motoru birebir simüle eder, ve buna ek olarak her
çözüm `REFERENCE_RUN` ile (§9.3) ve Dart motoruyla (§12) ikinci kez
doğrulanır.

**Tamlık ve optimallik.** Maliyeti `K` olan bir çözüm varsa, `search(budget = K)`
maliyeti `K` olan bir çözüm bulur (zaman sınırı olmadığı varsayımıyla).
*İspat taslağı:* En küçük bir çözüm `Q` alınır. L1 ile sola sıkıştırılır,
P-SYM ile fonksiyonları yeniden adlandırılır, P-TURN, P-COLOR ve P-PAINT
yeniden yazımları uygulanır. Bu yeniden yazımlar maliyeti artırmaz ve
davranışı korur. Sonra arama, `Q`'nun hücrelerini takip ederek ilerler:

- Her `OpenSlot`'ta `Q`'nun o slottaki hücresi ya aktif bir koşulla adaydır,
  ya ertelenen bir koşulla `CondOnly` olarak aday olur (aksiyonu daha sonra
  `NeedAction`'da seçilir), ya da `null`'dır ve bu `END` adayına karşılık gelir.
- P-EMPTYFN ve INV-FIN, `Q`'nun en küçük olmasıyla uyumludur.
- L7, `Q`'nun yolunu kesmez: `Q` başarıya ulaştığı için çalıştırmasında
  tekrar eden bir state yoktur.

Bütçe `1..K-1` turları tamamen tarandığı için, bulunan ilk çözüm en küçüktür.

---

## 11. Test planı

| Test | Neyi kilitler |
|---|---|
| `t_ref_*` | `REFERENCE_RUN`, tutorial bulmacalarında (`test/tutorial_levels_test.dart`'taki programlar) Dart ile aynı sonucu verir. |
| `t_step_limit_boundary` | State doğrudan kurulur: `steps = 19999` iken son yıldızı alan `Forward` → `Solved`, `steps = 20000`. `steps = 20000` iken aynı komut → `Dead(StepLimit)`, robot hareket etmemiş, yıldız yerinde. Aynı test `CondOnly` atlaması için de yapılır. |
| `t_tail_call` | R-TAIL: `F1: [Forward, Call F1]` stack'i büyütmez. |
| `t_diff_random` | **T-DIFF:** Rastgele, tamamen dolu fiziksel programlar (sabit tohum, ≥ 10⁵ adet) katalogdaki bulmacalarda hem `REFERENCE_RUN` hem `normalize` ile çalıştırılır. Sonuç, `steps` ve son state aynı olmalı (L4). |
| `t_loop_*` | Tail recursion döngüsü `Dead(Loop)` olarak yakalanır. Non-tail recursion `Dead(StepLimit)` ile biter. Yıldız alan bir "döngü" döngü sayılmaz. |
| `t_rebuild_middle` | `[B@k, C@j, B@k]` örneği (§6.3): END'den sonra ortadaki frame silinir, hash zinciri yeniden kurulur. |
| `t_p_sym`, `t_p_turn`, `t_p_paint`, `t_p_color`, `t_p_emptyfn` | Her budama kuralı hem pozitif hem negatif örnekle. |
| `t_p_turn_needaction` | `Red:?, Red:R` durumunda `?` için `L` üretilmez. |
| `t_e2e_tutorials` | Tutorial bulmacaları çözülür, maliyetleri beklenen en küçük değerlere eşit. |
| `t_e2e_bruteforce` | Küçük, elle kurulmuş bulmacalarda (toplam kapasite ≤ 4) bütün fiziksel programları deneyen saf bir kaba kuvvet ile aynı en küçük maliyet bulunur. **Optimalliğin asıl testi.** |
| Dart: `solver_solutions_test.dart` | §12. |

---

## 12. Çıktı formatı ve Dart doğrulaması

`solutions.json`:

```json
{
  "solver": "robozzle-solver 0.1.0",
  "maxSteps": 20000,
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
      "stats": { "millis": 12, "nodes": 45678, "nodesPerBudget": [1, 5, 40] }
    },
    { "sourceId": 53, "status": "timeout", "stats": { "millis": 60000, "nodes": 123456789 } }
  ]
}
```

- Her fonksiyon dizisinin uzunluğu `cap[f]`'ye eşittir; boş slotlar `null`.
- Komut yazımı: `"<koşul>:<aksiyon>"`. Koşul `Any` ise koşul kısmı yazılmaz.
  Koşul adları `red | green | blue`; aksiyon adları Dart'taki `ActionType`
  isimleriyle birebir aynı: `forward`, `turnLeft`, `turnRight`, `paintRed`,
  `paintGreen`, `paintBlue`, `callF1` … `callF5`. Böylece Dart tarafında
  `ActionType.values.byName(...)` ile doğrudan parse edilebilir.
- `status` değerleri: `solved | timeout | unsolvable`.

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
```

Her bulmaca için tek satır ilerleme çıktısı; sonunda zorluk seviyesine göre
özet: çözülen sayısı, ortalama süre, toplam node sayısı.

Paralellik: v1'de yok. v1.5'te bulmacalar arası paralellik (`rayon`) eklenir;
bu kolay ve güvenli, çünkü bulmacalar birbirinden bağımsız.

---

## 14. Modül yapısı

```text
solver/src/
  main.rs        CLI, rapor
  level.rs       JSON → Level, ön işleme (§3)
  program.rs     Cond, Action, Cell, FunctionDraft, PartialProgram, fiziksel program, serileştirme (§4.1–4.2, §12)
  reference.rs   REFERENCE_RUN (§2): basit, optimize edilmemiş, motorun birebir aynası
  machine.rs     Machine, stack arena, Zobrist (§4.3, §6, §7.3)
  normalize.rs   normalize (§5), döngü cache'i (§7)
  search.rs      aday üretimi (§8), IDDFS ve DFS (§9), finalize
```

Bağımlılıklar: `serde`, `serde_json`, `clap` (derive). Testlerde ek bağımlılık
yok; rastgelelik için `splitmix64` elle yazılır.

**Uygulama sırası:** `level` → `program` → `reference` (+ `t_ref`,
`t_step_limit`) → `machine` + `normalize` (+ `t_diff_random`) → `search`
(+ e2e testleri) → CLI → Dart testi → benchmark.

---

## 15. v1 kapsamı dışında (ölçümden sonra karar verilecek)

- Global transposition table. Gerekçe: bir kısmi programa arama ağacında tek bir yoldan ulaşılır, dolayısıyla tabloda eşleşme olmaz.
- Arama yolu boyunca taşınan döngü cache'i (§7.2).
- İstatistiğe dayalı sıralama (killer/history), `--any` modu (en kısa değil,
  herhangi bir çözüm).
- Aynı bulmaca içinde paralel arama.
- Non-tail recursion için pushdown analizi.
- İkincil hedef: aynı maliyette en az adım.

---
---

<a id="english"></a>

# Robozzle Solver — Design Specification (v1) — English

This document defines **what the solver does and why it is correct**. The code
is written against this document; if a rule changes, this document changes
first.

Rule IDs (`R-*`, `INV-*`, `P-*`, `T-*`) are referenced from code comments and
test names. For example, the code implementing a pruning rule carries a
`// P-TURN` comment and its tests are named `t_p_turn_*`.

---

## 0. Goal and principles

**Goal:** for every puzzle in `assets/levels_catalog.json`, find a program that
succeeds in the app's engine ([`lib/engine/interpreter.dart`](../lib/engine/interpreter.dart))
and uses the **fewest occupied slots**.

- **Primary objective:** minimize the number of non-empty slots.
- **Constraint:** the real engine's 20000-step limit. It is a constraint, not
  an objective.
- **Secondary objective (not in v1):** fewer steps at equal slot count.

Three principles override everything else:

1. **Engine semantics are sacred.** Every program the solver reports as a
   solution MUST produce `RunStatus.success` in the Dart engine (§2, §10).
2. **Prune only with proof.** A branch may be cut only if it can be *proven*
   that it contains no minimal solution. "Looks bad" is never a reason to
   prune; heuristics may only change the *order* in which branches are
   explored (§8.6).
3. **Determinism.** The same input always yields the same output. Search
   decisions never depend on `HashMap` iteration order.

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
- Stack depth is unbounded. The solver does **not** add a limit either.
- A star is collected only when the robot **enters** its tile. No catalog
  puzzle has a star on the start tile; if one did, that star would not count
  as collected until the robot re-entered the tile.

---

## 3. Input and preprocessing

### 3.1 Catalog

Each entry has `sourceId`, `rows` (list of strings), `startRow`, `startCol`,
`startDirection` (`up|right|down|left`), `slotsPerFunction` (5 numbers) and
`allowedCommands` (paint bitmask: `1` = red, `2` = green, `4` = blue).

Characters: `' '` or `'.'` is a gap; `r g b` is a colored tile; `R G B` is
the same color with a star on it.

Assumptions verified against the catalog (the loader asserts them): all rows
have the same length; the grid is at most 12×16 (192 tiles); the start tile is
never a gap; `cap[F1] > 0`; every puzzle has at least 1 star; `cap[f] ≤ 10`;
total capacity ≤ 50.

### 3.2 Precomputed static data (`Level`)

| Field | Definition |
|---|---|
| `TileId` | `row * cols + col`, `u8` (≤ 191). Gaps also get a `TileId` but have `is_tile = false`. |
| `neighbor[tile][dir]` | `Option<TileId>`. `None` if off the grid or a gap. |
| `init_color[tile]` | The tile's initial color. |
| `init_stars` | Set of star tiles, a `[u64; 3]` bitset. |
| `allowed_paints` | Set of colors derived from the `allowedCommands` bitmask. |
| `possible_colors` | `{colors initially on the grid} ∪ allowed_paints` (§8.2). |
| `cap[0..5]` | Function capacities. |
| `class_rep` | Capacity classes for F2..F5 (§8.4). |

Direction encoding: `Up = 0, Right = 1, Down = 2, Left = 3`.
`turn_left(d) = (d + 3) % 4`, `turn_right(d) = (d + 1) % 4`.

### 3.3 Static checks

- **P-CONN:** If any star lies outside the set of tiles reachable from the
  start tile (BFS), the puzzle returns `Unsolvable(Disconnected)` and search
  never starts. Painting does not change the grid's shape, so this check runs
  once.

---

## 4. Data structures

### 4.1 Instructions

```rust
enum Color { Red, Green, Blue }
enum Cond  { Any, Is(Color) }
enum Action { Forward, TurnLeft, TurnRight, Paint(Color), Call(FnId) }
```

### 4.2 Partial program

```rust
enum Cell {
    Resolved { cond: Cond, action: Action },
    CondOnly { cond: Color },          // condition chosen, action not yet
}

struct FunctionDraft {
    cells: Vec<Cell>,   // decided cells, left-packed
    ended: bool,        // true: everything after `cells` is definitely empty (END)
}

struct PartialProgram {
    fns: [FunctionDraft; 5],
    introduced: u8,     // bitmask: functions for which a call cell exists (§8.4)
    used: u8,           // cost: number of Resolved + CondOnly cells
}
```

Definitions:

- `len(f) = fns[f].cells.len()`.
- **Closed function:** `closed(f) := fns[f].ended || len(f) == cap[f]`.
- **Exhausted frame:** `exhausted(f, pc) := pc == len(f) && closed(f)`. Such a
  frame definitely has no instruction left to run.
- Physical form: `physical(f) = cells (all Resolved) ++ [null; cap[f] - len(f)]`.

**Lemma L1 (left packing).** Moving the `null` slots of a function to its end
does not change behavior. `null` slots are skipped and do not count as steps
(R-NULL). R-TAIL only asks "is any non-empty slot left after this one?", and
the answer is unchanged by the move. Functions are only entered at their
start; no instruction jumps to a slot index. So every physical program has a
unique left-packed form with the same behavior and the same cost, and
searching only left-packed forms loses no solution.

### 4.3 Machine

```rust
struct Machine {
    pos: TileId,
    dir: u8,
    colors: [Color; 192],   // plain array in v1
    stars: [u64; 3],
    star_count: u16,
    steps: u32,
    top: Option<Frame>,     // the running frame (its pc changes)
    rest: StackRef,         // suspended frames, persistent stack (§6)
    phys_hash: u128,        // Zobrist hash of pos, dir, stars, colors (§7.3)
}

struct Frame { f: u8, pc: u8 }
```

The machine is cloned at each frontier. It is about 250 bytes, so copying is
cheap; v1 does not use make/unmake (apply a change, then undo it).

---

## 5. `normalize()`: the execution layer

`normalize(P, M, seen) -> Outcome` advances machine `M` **in place** under
partial program `P`. The program is fixed; this function makes no decisions.

```rust
enum Outcome {
    Solved,
    Dead(DeadReason),                   // Crash | StepLimit | OutOfInstructions | Loop
    OpenSlot   { f: u8, pc: u8 },       // pc == len(f), function not closed
    NeedAction { f: u8, pc: u8, cond: Color },
}
```

```text
normalize(P, M, seen):                                          # N-*
    loop:
        if M.star_count == 0: return Solved                     # N-SOLVED
        if M.top is None:     return Dead(OutOfInstructions)
        (f, pc) = M.top

        if pc == len(f):                                        # N-END
            if closed(f): pop(M); continue                      # same as R-POP
            return OpenSlot{f, pc}                              # NO STEP, pc NOT ADVANCED

        match P.fns[f].cells[pc]:

            CondOnly{c}:                                        # N-CONDONLY
                if M.colors[M.pos] == c:
                    return NeedAction{f, pc, c}                 # NO STEP, pc NOT ADVANCED
                if !consume_step(M): return Dead(StepLimit)
                M.top.pc += 1
                continue                                        # condition false, skip

            Resolved{cond, action}:                             # N-RESOLVED
                if !consume_step(M): return Dead(StepLimit)     # R-STEP: limit FIRST
                M.top.pc += 1
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
                        if seen.check_and_insert(M):            # §7
                            return Dead(Loop)

consume_step(M):
    M.steps += 1
    return M.steps <= MAX_STEPS
```

Cells never call a function with `cap[g] == 0` (§8.3), so the branch at
R-RUN (232) needs no counterpart.

**Lemma L2 (stopping at a frontier).** At `OpenSlot` and `NeedAction` the
machine is in the state **immediately before** the slot is evaluated: no step
has been counted and `pc` has not advanced. Once the decision is made,
`normalize` evaluates the same slot from scratch, exactly as the engine
would. So every non-empty slot is counted exactly once.

**Lemma L3 (resuming from a frontier).** Execution up to the frontier never
read the cell being decided; if it had, it would have stopped there. So every
child branch can resume from a copy of the frontier machine instead of
re-running from the start.

**Lemma L4 (equivalence).** If every cell of `P` is `Resolved` and `normalize`
ends with `Solved`, `Crash`, `StepLimit` or `OutOfInstructions` without
reaching a frontier, then `REFERENCE_RUN(physical(P))` gives the same
outcome, the same `steps` and the same final state. When `normalize` returns
`Loop`, the reference run either returns `STUCK` or never terminates. This
lemma is checked by the T-DIFF test.

---

## 6. Stack

### 6.1 Representation

The running frame (`M.top`) is mutable and its `pc` advances with every
instruction. The `pc` of a suspended frame **never changes while it is
suspended**, so suspended frames live in a persistent linked list:

```rust
struct StackNode { frame: Frame, parent: StackRef, depth: u32, hash: u128 }
type StackRef = Option<NodeId>;          // NodeId = u32 index into the arena

node.hash = mix(parent.hash (0 if none), frame.f, frame.pc)
stack_hash(M) = mix(hash(M.rest), M.top.f, M.top.pc)
```

- **Arena:** `Vec<StackNode>`. The search is depth-first, so allocation
  follows a stack discipline: when a child branch returns,
  `arena.truncate(mark)`. Nothing references the nodes that branch created
  any more.
- A cache entry does not copy the stack; it stores a single `NodeId`. So
  each entry costs O(1) memory even with deep recursion.

### 6.2 Operations

```text
call(P, M, g):                                                   # S-CALL
    if exhausted(M.top.f, M.top.pc):      # R-TAIL: caller has definitely nothing left
        M.top = (g, 0)                    # replace
    else:
        M.rest = push_node(M.rest, M.top) # suspend
        M.top  = (g, 0)

pop(M):                                                          # S-POP
    if M.rest is None: M.top = None
    else: M.top = node(M.rest).frame; M.rest = node(M.rest).parent
```

**Difference from the engine, and why it is equivalent.** For R-TAIL the
engine asks "are all remaining physical slots `null`?". We ask
`exhausted(...)`. If the caller's remainder still contains an undecided slot
(the function is not closed), we keep the frame; the engine would drop it if
that slot later turned out to be `null`. This difference does not change
behavior (see the R-TAIL note); it only changes how the stack is
represented. The rule in §6.3 restores the canonical representation.

### 6.3 Canonical stack (INV-STACK)

**INV-STACK:** No suspended frame is `exhausted`. The running frame (`top`)
may be exhausted; it is then popped at the top of the loop.

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

**S-REBUILD:** After an END decision, on **that child branch's** machine copy
only:

```text
frames = collect the M.rest chain, bottom to top
frames = [fr for fr in frames if !(fr.f == f and fr.pc == k)]
M.rest = push frames onto the arena again (hash chain recomputed)
```

This costs O(depth), paid once per END decision rather than once per call.
Frames can be removed from the **middle** of the stack. Example: with
`[B@k, C@j, B@k (top)]`, if slot k of B is decided as END, the top pops, C
keeps running, and the lower `B@k` is removed.

---

## 7. Loop detection

### 7.1 Rule

After a `Call` completes (after S-CALL), compute the machine's **loop key**:

```text
key(M) = (pos, dir, stars, colors, [frames in rest], top)     # steps NOT included
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

`seen` **starts empty on every `normalize` call**: in v1 a fresh cache is
opened after every synthesis decision.

*Rationale (to be copied into the code as-is):* Suppose a state `S` was seen
before a decision and is seen again after it. At the second sighting, every
cell read on the `S → … → S` path is now fixed in the program, and cells
added later cannot affect that path. So carrying the cache along the current
search path **would also** be safe. The only thing that is **not** safe is
sharing the cache between sibling branches. v1 resets the cache on every
decision because it is simpler; the cost is that a loop is detected at most
one iteration later.

### 7.3 Hashing and exact equality

- `phys_hash`: Zobrist hashing. `u128` tables generated by a fixed-seed
  `splitmix64`: `ROBOT[tile][dir]`, `STAR[tile]`, `COLOR[tile][color]`.
  Moving, turning, painting and collecting a star update the hash in O(1)
  with XOR.
- `key_hash = mix(phys_hash, stack_hash(M))`.
- `seen: HashMap<u128, Vec<SeenEntry>>`. On a hash match, **exact equality**
  is checked: `pos`, `dir`, `stars`, `colors`, and the stack chain (frame by
  frame until both reach the same `NodeId` or the root). `SeenEntry` stores a
  copy of the color array (192 bytes).

Note: a hash collision would cause a wrong *prune*, i.e. a missed solution;
it could not produce a wrong solution. Exact equality is still mandatory in
v1.

---

## 8. Candidate generation

### 8.1 Frontier kinds and cost

| Frontier | Candidates | Cost |
|---|---|---|
| `OpenSlot{f, pc}` | `END` | +0 |
| | `Resolved{cond ∈ active conditions, action}` | +1 |
| | `CondOnly{c}` for each deferred condition `c` | +1 |
| `NeedAction{f, pc, c}` | replace with `Resolved{Is(c), action}` | +0 |

Candidates with `used + cost > budget` are not generated. At an `OpenSlot`
with the budget exhausted, only `END` remains.

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

### 8.3 Actions

Candidate actions for a cell with condition `cond` (`Is(c)` for `NeedAction`):

```text
Forward, TurnLeft, TurnRight,
Paint(x)  for x in allowed_paints,
Call(g)   for g in callable(P)                       (§8.4)
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
  introduced from the start.
- Capacity classes: among `F2..F5`, functions with `cap > 0` are grouped by
  capacity. `F1` is in no class: as the entry point it cannot be swapped with
  the others.
- `callable(P) = introduced ∪ { the lowest-index not-yet-introduced function of each class }`.

Example: for `cap = [6, 6, 0, 6, 0]` (catalog puzzle #2973) the callable set
starts as `{F1, F2}`. Once `F2` is introduced, `F4` becomes callable too.

*Proof:* swapping the names of two functions with the same capacity (and all
calls to them) gives a valid program with the same cost, and execution is
unchanged. In any solution, each class can be renamed in the order in which
its functions are first introduced. That order is determined by execution
itself, so the renamed program satisfies this rule and the search finds it.
This does **not** hold across different capacities: a 4-slot body may not
fit into a 2-slot function.

### 8.5 Local equivalence pruning

After a cell is placed at index `i`, the windows containing `i` are checked:
`[i-2, i+2]`. At a `NeedAction`, cells to the right may already be filled, so
both directions are checked.

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
budget iteration reaches a solution. A fixed order is enough for v1:

```text
OpenSlot:   Any:Forward, cur:Forward, Any:Call(introduced), Any:TurnLeft, Any:TurnRight,
            cur:(same order), Any:Call(new), Paint…, CondOnly…, END
NeedAction: Forward, Call(introduced), TurnLeft, TurnRight, Call(new), Paint…
```

---

## 9. Search

### 9.1 Outer loop: iterative deepening on budget (IDDFS)

```text
solve(level, limits):
    if P-CONN fails: return Unsolvable(Disconnected)
    for budget in 1 ..= sum(cap):
        root_program = empty (all functions open, used = 0, introduced = {F1})
        root_machine = initial state, top = (F1, 0), rest = None
        match search(root_program, root_machine, budget):
            Found(p)  → return Solved(finalize(p))
            Timeout   → return Timeout
            NotFound  → continue
    return Unsolvable(Exhausted)    # no solution at any budget (under engine semantics)
```

`budget = 0` is skipped: every puzzle has at least one star, so the empty
program is never a solution.

### 9.2 Inner loop: DFS

```text
search(P, M, budget):
    limits.check()?                                  # time and node limits → Timeout
    seen = new cache
    match normalize(P, &mut M, &mut seen):
        Solved         → return Found(P)
        Dead(_)        → return NotFound
        OpenSlot{f,pc} →
            for cand in open_candidates(P, M, f, pc, budget):     # §8, ordered
                (P2, M2) = (P.clone(), M.clone())
                apply(P2, cand)                      # cells.push / ended = true
                if cand == END: S-REBUILD(M2, f, pc)
                r = search(P2, M2, budget)?
                if r is Found: return r
            return NotFound
        NeedAction{f,pc,c} →
            for act in need_candidates(P, M, f, pc, c):
                (P2, M2) = (P.clone(), M.clone())
                P2.fns[f].cells[pc] = Resolved{Is(c), act}
                r = search(P2, M2, budget)?
                if r is Found: return r
            return NotFound
```

Each `search` call counts as one **node**; statistics report nodes per
budget.

### 9.3 `finalize`

```text
finalize(P):
    assert (INV-FIN) all cells are Resolved       # debug_assert
    physical = for each f: cells ++ null * (cap[f] - len(f))
    assert REFERENCE_RUN(physical) == SUCCESS     # always, release builds too
    return (physical, P.used, steps)
```

**INV-FIN:** No `CondOnly` cell can remain in the first solution found.
(*Proof:* a `CondOnly` that never fired was skipped every time it was
reached. Removing it keeps the behavior and lowers both the step count and
the cost by 1. Then a solution would exist at `budget - 1`, but that
iteration already failed. Contradiction.) If this assert ever fires, there is
a bug.

Function tails left undecided become `null` in the output. They are never
reached, so they have no effect and do not count toward the cost.

---

## 10. Correctness summary

**Soundness.** Every returned program succeeds in the engine: by L1–L5,
`normalize` simulates the engine exactly, and on top of that every solution
is re-checked with `REFERENCE_RUN` (§9.3) and with the Dart engine (§12).

**Completeness and optimality.** If a solution of cost `K` exists,
`search(budget = K)` finds a solution of cost `K` (assuming no time limit).
*Proof sketch:* take a minimal solution `Q`. Left-pack it (L1), rename its
functions (P-SYM), and apply the P-TURN, P-COLOR and P-PAINT rewrites. None
of these rewrites increases cost, and all preserve behavior. The search then
follows `Q`'s cells:

- At each `OpenSlot`, `Q`'s cell at that slot is either a candidate with an
  active condition, a `CondOnly` candidate with a deferred condition (its
  action is chosen later at a `NeedAction`), or `null`, which corresponds to
  the `END` candidate.
- P-EMPTYFN and INV-FIN are consistent with `Q` being minimal.
- L7 does not cut `Q`'s path: `Q` reaches success, so its execution has no
  repeating state.

Budgets `1..K-1` are searched exhaustively, so the first solution found is
minimal.

---

## 11. Test plan

| Test | What it locks down |
|---|---|
| `t_ref_*` | `REFERENCE_RUN` matches Dart on the tutorial puzzles (the programs in `test/tutorial_levels_test.dart`). |
| `t_step_limit_boundary` | Build the state directly: at `steps = 19999`, a `Forward` that collects the last star → `Solved`, `steps = 20000`. At `steps = 20000`, the same instruction → `Dead(StepLimit)`, the robot has not moved, the star is still there. The same test is repeated for a skipped `CondOnly`. |
| `t_tail_call` | R-TAIL: `F1: [Forward, Call F1]` does not grow the stack. |
| `t_diff_random` | **T-DIFF:** random fully-filled physical programs (fixed seed, ≥ 10⁵ of them) run on catalog puzzles through both `REFERENCE_RUN` and `normalize`. Outcome, `steps` and final state must match (L4). |
| `t_loop_*` | A tail-recursive loop is caught as `Dead(Loop)`. Non-tail recursion ends in `Dead(StepLimit)`. A "loop" that collects a star is not a loop. |
| `t_rebuild_middle` | The `[B@k, C@j, B@k]` example (§6.3): after END, the middle frame is removed and the hash chain is rebuilt. |
| `t_p_sym`, `t_p_turn`, `t_p_paint`, `t_p_color`, `t_p_emptyfn` | Each pruning rule, with both positive and negative examples. |
| `t_p_turn_needaction` | With `Red:?, Red:R`, `L` is not generated for `?`. |
| `t_e2e_tutorials` | The tutorial puzzles are solved at their expected minimal costs. |
| `t_e2e_bruteforce` | On small hand-built puzzles (total capacity ≤ 4), the solver finds the same minimal cost as a naive brute force that tries every physical program. **The real optimality test.** |
| Dart: `solver_solutions_test.dart` | §12. |

---

## 12. Output format and Dart verification

`solutions.json`:

```json
{
  "solver": "robozzle-solver 0.1.0",
  "maxSteps": 20000,
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
      "stats": { "millis": 12, "nodes": 45678, "nodesPerBudget": [1, 5, 40] }
    },
    { "sourceId": 53, "status": "timeout", "stats": { "millis": 60000, "nodes": 123456789 } }
  ]
}
```

- Each function array has length `cap[f]`; empty slots are `null`.
- Instruction syntax: `"<condition>:<action>"`. When the condition is `Any`,
  the condition part is omitted. Condition names are `red | green | blue`;
  action names are exactly Dart's `ActionType` names: `forward`, `turnLeft`,
  `turnRight`, `paintRed`, `paintGreen`, `paintBlue`, `callF1` … `callF5`. So
  the Dart side can parse them directly with `ActionType.values.byName(...)`.
- `status` values: `solved | timeout | unsolvable`.

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
```

One progress line per puzzle; at the end, a summary by difficulty: puzzles
solved, average time, total nodes.

Parallelism: none in v1. v1.5 adds parallelism across puzzles (`rayon`),
which is easy and safe because puzzles are independent.

---

## 14. Module layout

```text
solver/src/
  main.rs        CLI, report
  level.rs       JSON → Level, preprocessing (§3)
  program.rs     Cond, Action, Cell, FunctionDraft, PartialProgram, physical program, serialization (§4.1–4.2, §12)
  reference.rs   REFERENCE_RUN (§2): simple, unoptimized, an exact mirror of the engine
  machine.rs     Machine, stack arena, Zobrist (§4.3, §6, §7.3)
  normalize.rs   normalize (§5), loop cache (§7)
  search.rs      candidate generation (§8), IDDFS and DFS (§9), finalize
```

Dependencies: `serde`, `serde_json`, `clap` (derive). No extra test
dependencies; `splitmix64` is written by hand for randomness.

**Implementation order:** `level` → `program` → `reference` (+ `t_ref`,
`t_step_limit`) → `machine` + `normalize` (+ `t_diff_random`) → `search`
(+ e2e tests) → CLI → Dart test → benchmark.

---

## 15. Out of scope for v1 (to be decided after measuring)

- Global transposition table. Rationale: a partial program is reached by
  exactly one path in the search tree, so the table would get no hits.
- A loop cache carried along the search path (§7.2).
- Statistics-based ordering (killer/history), an `--any` mode (any solution
  rather than the shortest).
- Parallel search within a single puzzle.
- Pushdown analysis for non-tail recursion.
- Secondary objective: fewest steps at equal cost.

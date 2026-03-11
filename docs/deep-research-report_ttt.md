# Empfehlungen für extrem schnelles Transkript‑Post‑Editing auf Low‑End‑Notebook‑CPU

## Executive Empfehlung

Für **maximale Geschwindigkeit** auf einem **4–8‑Core Notebook mit ~16 GB RAM** und **kommerziell verteilter Open‑Source‑App** (Lizenz muss „unkompliziert“ sein) sind **Apache‑2.0‑Modelle** ideal. Daher empfehle ich als zwei „Base“-Optionen:

- **Qwen2.5‑1.5B‑Instruct (Apache‑2.0)**: Sehr schneller Allrounder mit **Deutsch ausdrücklich im Sprachumfang**; gute Rewrite/Summarize‑Eignung für die Größe. citeturn25view0turn5search3  
- **SmolLM2‑1.7B‑Instruct (Apache‑2.0)**: Ebenfalls sehr schnell und in der Model‑Card explizit für **Text rewriting / Summarization** vorgesehen; aber **primär Englisch** → für DE eher „okay“ als „top“. citeturn10view0turn1view2turn5search3  

Als **„gehoben“ (mehr Qualität, noch low‑end‑tauglich)**:

- **Qwen3.5‑4B (Apache‑2.0)** in **Q4_K_M oder Q5_K_M**: deutlich stärkere Instruction‑Following‑Scores (IFEval) und sehr breite Mehrsprachigkeit; bleibt in Q4/Q5 noch im 16‑GB‑Rahmen. citeturn12view1turn4view0turn12view0  

CPU‑Performance‑Anker (für realistische Erwartung): Auf **Intel Core Ultra 7 155H** liegen (llama.cpp / CPU‑BLAS) **~7.2 tok/s** für ein 8B‑Q8 und **~26.8 tok/s** für ein 3B‑Q8 (tg128). citeturn19view0  
Auf einem deutlich schwächeren **Intel i5‑1334U** wird ein 3B‑Q8 in der tg128‑Konfiguration mit **~8 tok/s** berichtet. citeturn21view0  

## Kurzvergleich der drei empfohlenen Modelle

| Empfehlung | Params | Lizenz | Empf. GGUF‑Quant | Disk (Quant) | Disk (F16/BF16) | Deutsch | Speed‑Erwartung (tg) |
|---|---:|---|---|---:|---:|---|---|
| Qwen2.5‑1.5B‑Instruct | 1.54B citeturn25view0 | Apache‑2.0 citeturn25view0 | Q5_0 (oder Q4_K_M) citeturn25view0 | ~1.26 GB (Q5_0) citeturn25view0 | ~3.1 GB (≈2 B/Param, Schätzung) | ja (u. a. Deutsch) citeturn25view0 | i5‑U: grob ~12–20 tok/s; i7/R7‑U/H: ~25–45 tok/s (aus 3B/8B‑Ankern skaliert) citeturn19view0turn21view0 |
| SmolLM2‑1.7B‑Instruct | 1.7B citeturn10view0 | Apache‑2.0 citeturn10view0 | Q4_K_M (offiziell) citeturn26view0 | ~1.06 GB citeturn26view0 | ~3.4 GB (Schätzung) | eher EN‑fokussiert citeturn10view0 | ähnlich Qwen2.5‑1.5B; ggf. minimal langsamer (mehr Params) |
| Qwen3.5‑4B | 4B citeturn12view1 | Apache‑2.0 citeturn12view0 | Q4_K_M (oder Q5_K_M) citeturn4view0 | ~2.74 GB (Q4_K_M) / ~3.14 GB (Q5_K_M) citeturn4view0 | ~8.42 GB (BF16) citeturn4view0 | sehr breit (201 Sprachen/Dialekte) citeturn12view1 | i5‑U: grob ~4–8 tok/s; i7/R7‑U/H: ~10–20 tok/s (aus 3B/8B‑Ankern skaliert) citeturn19view0turn21view0 |

**Hinweis**: Qwen3.5‑4B ist als „Causal LM mit Vision Encoder“ beschrieben; für Text‑Post‑Editing nutzt du einfach den Text‑Pfad. citeturn11view0  

## Base‑Modell A: Qwen2.5‑1.5B‑Instruct (Apache‑2.0)

**Kernparameter & Dateien**
- **Params:** 1.54B; **Kontext:** 32,768 (Generation 8,192). citeturn25view0  
- **Empfohlene Datei:** `qwen2.5-1.5b-instruct-q5_0.gguf` (Fallback: `q4_k_m`). Quant‑Liste inkl. Q4_0/Q5_0/Q8_0 im offiziellen GGUF‑Repo. citeturn25view0  
- **Disk:** z. B. **Q5_0 ~1.26 GB**, Q8_0 ~1.89 GB (offizielle Größenangaben). citeturn25view0  

**Qualität/Instrukt‑Proxies**
- In einer Vergleichstabelle im SmolLM2‑Model‑Card: **IFEval 47.4**, **MT‑Bench 6.52**, **OpenRewrite RougeL 46.9** (als Proxy für Rewrite/Summarize). citeturn5search3  

**Deutsch‑Fähigkeit**
- Offiziell: „Multilingual support … including … German“. citeturn25view0  

**CPU & Performance**
- llama.cpp/Ökosystem ist stark von SIMD/ISA (AVX2/AVX‑512) und BLAS‑Builds geprägt. citeturn5search2  
- Erwartung auf Low‑End CPU: aus 3B‑Ankern (i5‑1334U ~8 tok/s bei 3B Q8) lässt sich für 1.5B **~12–20 tok/s** als grobe Praxis‑Spanne ableiten (Chunk‑abhängig). citeturn21view0turn19view0  

**Threads & Kontext**
- Startwert: `--threads = physische Kerne` (bei 4–8 Cores oft 4–8). Thread‑Skalierung zeigt starke Gewinne bis ~8 Threads und dann Sättigung in llama‑bench‑Beispielen. citeturn14view1  
- Für 4k–8k Workflows: `--ctx-size 4096` oder `8192`; lieber **Chunking** statt riesigem Kontext (KV‑Cache wächst mit Kontext). (Prompt‑/Gen‑Trennung in llama‑bench ist genau dafür gedacht.) citeturn14view1  

## Base‑Modell B: SmolLM2‑1.7B‑Instruct (Apache‑2.0)

**Kernparameter & Dateien**
- **Params:** 1.7B; Apache‑2.0 Lizenz. citeturn10view0  
- Offizielles GGUF‑Bundle im HF‑Tree bietet **Q4_K_M** mit **~1.06 GB** und direktem `--hf-repo/--hf-file`‑Pull. citeturn26view0  

**Qualität/Instrukt‑Proxies**
- **IFEval 56.7**, **MT‑Bench 6.13**, **OpenRewrite RougeL 44.9** (Model‑Card‑Tabelle). citeturn5search3  

**Deutsch‑Eignung**
- Limitation: „primarily understand and generate content in English“ → für DE‑Post‑Editing eher zweite Wahl. citeturn10view0  

**CPU & Performance**
- Ähnlich Qwen2.5‑1.5B; minimal langsamer möglich (mehr Params), aber weiterhin „sehr schnell“ auf 4–8 Cores (bei Q4‑Quant). Performance ist stark Build/ISA‑abhängig (AVX2/FMA typisch auf Office‑CPUs). citeturn5search2turn20search11turn27search1  

## Gehobenes Modell: Qwen3.5‑4B (Apache‑2.0) – noch low‑end‑tauglich

**Warum „gehoben“**
- Model‑Card zeigt sehr starke **Instruction Following**‑Werte (z. B. IFEval 89.8) sowie breite Multilingual‑Benchmarks; außerdem „Global Linguistic Coverage“ mit **201 Sprachen/Dialekten**. citeturn12view1turn11view0  

**Dateien / Footprint**
- Empfohlen: **Q4_K_M ~2.74 GB** (schneller/leichter) oder **Q5_K_M ~3.14 GB** (mehr Qualität). BF16‑Variante ~8.42 GB. citeturn4view0  
- In 16 GB RAM mit `ctx=4096–8192` i. d. R. machbar; KV‑Cache ist der Haupt‑RAM‑Treiber → Kontext bewusst klein halten. citeturn14view1  

**Performance‑Erwartung**
- Als 4B liegt es zwischen 3B und 8B. Mit den OpenBenchmark‑Ankern (3B Q8 auf i5‑1334U ~8 tok/s; 8B Q8 auf 155H ~7.2 tok/s; 3B Q8 auf 155H ~26.8 tok/s) ist für low‑end i5‑U grob **~4–8 tok/s** plausibel, für stärkere U/H‑CPUs **~10–20 tok/s** (je nach Quant/Build/Throttling). citeturn21view0turn19view0  

## Go‑Integration praxisnah

**CLI vs cgo**
- Für schnelle Produktintegration: `llama-cli` via `os/exec`. Qwen‑GGUF‑Repo zeigt CLI‑Nutzung und Download via `huggingface-cli`. citeturn25view0  
- Für integriertes Model‑Handling und HF‑Download direkt aus llama.cpp: SmolLM2‑GGUF zeigt `llama-cli --hf-repo ... --hf-file ...` (benötigt Build mit CURL). citeturn26view0  

**mmap & Threads**
- `llama-bench` dokumentiert `--mmap` (default an) und `--threads`. Für Desktop‑Apps ist „mmap an“ meist sinnvoll (geringerer Peak‑RAM, schnellerer Start). citeturn14view1  

**Go‑CLI‑Beispiel (kurz)**
```go
cmd := exec.CommandContext(ctx, llamaPath,
  "-m", modelPath,
  "--threads", "6",
  "--ctx-size", "4096",
  "-n", "256",
  "--temp", "0.2",
  "-p", prompt,
)
out, err := cmd.CombinedOutput()
```

## 5‑Schritte Quick‑Setup zum Testen auf 4–8 Cores / 16 GB

1) **Modell wählen:** Qwen2.5‑1.5B‑Instruct‑GGUF (Q5_0) als Start. citeturn25view0  
2) **Download (reproduzierbar):** `huggingface-cli download … --include "<gguf>"` oder `llama-cli --hf-repo/--hf-file` (Smol). citeturn25view0turn26view0  
3) **llama.cpp Build:** CPU‑BLAS‑Variante testen (OpenBenchmarking‑Profil nutzt CPU‑BLAS häufig). citeturn5search2turn19view0  
4) **Erst‑Benchmark:** `llama-bench` für pp/tg verwenden und Threads 4,6,8 vergleichen (Thread‑Sättigung beachten). citeturn14view1  
5) **Workflow‑Tuning:** `ctx=4096` + Chunking; erst wenn stabil, `ctx=8192` versuchen; dann optional Upgrade auf Qwen3.5‑4B Q4_K_M. citeturn4view0turn14view1turn12view1
function helperSlaInfo {
    param([string]$Client = 'All')

    $slaOutput = @"
┌──────────────────────────────────────────────────────────────────────┐
│                  INFORMASI SLA OPERASIONAL TEKNIS                    │
│               [Sumber: Project PT Taspen (Persero) 2025]             │
├──────────────────────┬──────────────────────┬────────────────────────┤
│ SEVERITY LEVEL       │ RESPONSE TIME        │ RESOLUTION TIME        │
├──────────────────────┼──────────────────────┼────────────────────────┤
│ Severity 1 (Critical)│ 15 Menit             │ 1 Jam                  │
│ Severity 2 (High)    │ 30 Menit             │ 2 Jam                  │
│ Severity 3 (Medium)  │ 45 Menit             │ 4 Jam                  │
│ Severity 4 (Low)     │ 60 Menit             │ 12 Jam                 │
└──────────────────────┴──────────────────────┴────────────────────────┘
  Catatan Metrik:
  * Response Time   : Waktu tanggap awal setelah laporan diterima.
  * Resolution Time : Waktu penyelesaian insiden / pemulihan teknis.

┌──────────────────────────────────────────────────────────────────────┐
│                  KEPATUHAN HUKUM & REGULASI NASIONAL                 │
│         [Sumber: UU No. 27 Tahun 2022 tentang PDP - Pasal 46]        │
├──────────────────────────────────────────────────────────────────────┤
│ Ketentuan Notifikasi Kegagalan Data:                                 │
│ Dalam hal terjadi kegagalan Pelindungan Data Pribadi, Pengendali     │
│ Data Pribadi wajib menyampaikan pemberitahuan tertulis paling lambat │
│ 3 x 24 (tiga kali dua puluh empat) jam kepada:                       │
│   a. Subjek Data Pribadi; dan                                        │
│   b. Lembaga.                                                        │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│             KERANGKA MANAJEMEN INSIDEN INTERNASIONAL                 │
│         [Sumber Internasional: NIST SP 800-61 Rev. 2 Guide]          │
├──────────────────────────────────────────────────────────────────────┤
│ Incident Response Life Cycle & Prioritization:                       │
│ Mengatur alur 4 tahap (Preparation, Detection & Analysis,            │
│ Containment/Eradication/Recovery, Post-Incident Activity).           │
│ Penentuan prioritas wajib mengombinasikan Functional Impact,         │
│ Information Impact, dan Recoverability penanganan insiden.           │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│             STANDAR MANAJEMEN LAYANAN & SLA INTERNASIONAL            │
│      [Sumber Internasional: ISO/IEC 27035 & ISO/IEC 20000-1]         │
├──────────────────────────────────────────────────────────────────────┤
│ Incident Management & Service Level Requirements:                    │
│ Wajib menetapkan, mendokumentasikan, dan mengaudit target waktu      │
│ penanganan insiden (Response & Resolution Time) secara terukur       │
│ pada dokumen SLA/OLA resmi sesuai tingkat prioritas dampak bisnis.   │
└──────────────────────────────────────────────────────────────────────┘
"@

    Write-Host $slaOutput
}
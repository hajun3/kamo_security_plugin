#!/usr/bin/env bash
# ============================================================
# KM Security Plugin - 보안 로그 대시보드 생성기
#
# 사용법:
#   ./generate-dashboard.sh                    # 오늘 로그
#   ./generate-dashboard.sh 2026-04-02         # 특정 날짜
#   ./generate-dashboard.sh 2026-04-01 2026-04-07  # 기간 범위
#
# 결과: ~/.claude/security-logs/dashboard.html 생성 후 브라우저에서 열림
# ============================================================
set -euo pipefail

LOG_DIR="$HOME/.claude/security-logs"
OUTPUT="$LOG_DIR/dashboard.html"

# 날짜 파라미터 처리
if [ $# -eq 0 ]; then
    START_DATE=$(date +%Y-%m-%d)
    END_DATE="$START_DATE"
elif [ $# -eq 1 ]; then
    START_DATE="$1"
    END_DATE="$1"
else
    START_DATE="$1"
    END_DATE="$2"
fi

# 로그 파일 수집 및 병합
MERGED_LOGS=""
current="$START_DATE"
while [[ "$current" < "$END_DATE" ]] || [[ "$current" == "$END_DATE" ]]; do
    log_file="$LOG_DIR/${current}.jsonl"
    if [ -f "$log_file" ]; then
        MERGED_LOGS+=$(cat "$log_file")
        MERGED_LOGS+=$'\n'
    fi
    current=$(date -d "$current + 1 day" +%Y-%m-%d 2>/dev/null || date -v+1d -jf "%Y-%m-%d" "$current" +%Y-%m-%d)
done

if [ -z "$MERGED_LOGS" ]; then
    echo "⚠️  해당 기간의 로그가 없습니다: $START_DATE ~ $END_DATE"
    exit 0
fi

# JSON 배열로 변환
LOG_JSON=$(echo "$MERGED_LOGS" | grep -v '^$' | jq -s '.')

# 통계 계산
TOTAL=$(echo "$LOG_JSON" | jq 'length')
BLOCKED=$(echo "$LOG_JSON" | jq '[.[] | select(.status == "BLOCKED")] | length')
ALLOWED=$(echo "$LOG_JSON" | jq '[.[] | select(.status == "ALLOWED")] | length')
EXECUTED=$(echo "$LOG_JSON" | jq '[.[] | select(.status == "EXECUTED")] | length')

# 카테고리별 차단 집계
CATEGORY_STATS=$(echo "$LOG_JSON" | jq '
    [.[] | select(.status == "BLOCKED")]
    | group_by(.category)
    | map({category: .[0].category, count: length})
    | sort_by(-.count)
')

# 최근 차단 목록 (최신 20건)
RECENT_BLOCKS=$(echo "$LOG_JSON" | jq '
    [.[] | select(.status == "BLOCKED")]
    | sort_by(.timestamp)
    | reverse
    | .[0:20]
')

# 시간대별 활동
HOURLY_STATS=$(echo "$LOG_JSON" | jq '
    group_by(.timestamp[11:13])
    | map({
        hour: .[0].timestamp[11:13],
        total: length,
        blocked: [.[] | select(.status == "BLOCKED")] | length
    })
    | sort_by(.hour)
')

# HTML 대시보드 생성
cat > "$OUTPUT" << 'HTMLSTART'
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>🔒 KM Security Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
  @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;700&family=Noto+Sans+KR:wght@300;400;600;700&display=swap');
  
  * { margin: 0; padding: 0; box-sizing: border-box; }
  
  :root {
    --bg: #0a0e17;
    --card: #111827;
    --card-hover: #1a2332;
    --border: #1e293b;
    --text: #e2e8f0;
    --text-dim: #64748b;
    --accent: #3b82f6;
    --red: #ef4444;
    --red-glow: rgba(239, 68, 68, 0.15);
    --green: #22c55e;
    --green-glow: rgba(34, 197, 94, 0.15);
    --yellow: #eab308;
    --yellow-glow: rgba(234, 179, 8, 0.15);
    --purple: #a855f7;
  }
  
  body {
    font-family: 'Noto Sans KR', sans-serif;
    background: var(--bg);
    color: var(--text);
    min-height: 100vh;
    padding: 2rem;
  }
  
  .header {
    text-align: center;
    margin-bottom: 2.5rem;
    padding-bottom: 1.5rem;
    border-bottom: 1px solid var(--border);
  }
  
  .header h1 {
    font-size: 1.8rem;
    font-weight: 700;
    letter-spacing: -0.02em;
    margin-bottom: 0.3rem;
  }
  
  .header .period {
    font-family: 'JetBrains Mono', monospace;
    font-size: 0.9rem;
    color: var(--text-dim);
  }
  
  /* Stats Cards */
  .stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 1rem;
    margin-bottom: 2rem;
  }
  
  .stat-card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 1.5rem;
    text-align: center;
    transition: transform 0.2s, border-color 0.2s;
  }
  
  .stat-card:hover {
    transform: translateY(-2px);
    border-color: var(--accent);
  }
  
  .stat-card .number {
    font-family: 'JetBrains Mono', monospace;
    font-size: 2.5rem;
    font-weight: 700;
    line-height: 1;
    margin-bottom: 0.3rem;
  }
  
  .stat-card .label {
    font-size: 0.85rem;
    color: var(--text-dim);
    font-weight: 400;
  }
  
  .stat-card.blocked { border-left: 3px solid var(--red); }
  .stat-card.blocked .number { color: var(--red); }
  .stat-card.allowed { border-left: 3px solid var(--green); }
  .stat-card.allowed .number { color: var(--green); }
  .stat-card.total { border-left: 3px solid var(--accent); }
  .stat-card.total .number { color: var(--accent); }
  .stat-card.rate { border-left: 3px solid var(--yellow); }
  .stat-card.rate .number { color: var(--yellow); }
  
  /* Charts Row */
  .charts-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1rem;
    margin-bottom: 2rem;
  }
  
  @media (max-width: 768px) {
    .charts-row { grid-template-columns: 1fr; }
  }
  
  .chart-card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 1.5rem;
  }
  
  .chart-card h3 {
    font-size: 0.95rem;
    font-weight: 600;
    margin-bottom: 1rem;
    color: var(--text-dim);
  }
  
  /* Event Log Table */
  .log-section {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 1.5rem;
    overflow-x: auto;
  }
  
  .log-section h3 {
    font-size: 0.95rem;
    font-weight: 600;
    margin-bottom: 1rem;
    color: var(--text-dim);
  }
  
  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.85rem;
  }
  
  th {
    text-align: left;
    padding: 0.6rem 0.8rem;
    border-bottom: 1px solid var(--border);
    color: var(--text-dim);
    font-weight: 600;
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  
  td {
    padding: 0.6rem 0.8rem;
    border-bottom: 1px solid rgba(30, 41, 59, 0.5);
    font-family: 'JetBrains Mono', monospace;
    font-size: 0.8rem;
  }
  
  tr:hover { background: var(--card-hover); }
  
  .badge {
    display: inline-block;
    padding: 0.15rem 0.5rem;
    border-radius: 4px;
    font-size: 0.7rem;
    font-weight: 600;
  }
  
  .badge.blocked { background: var(--red-glow); color: var(--red); }
  .badge.allowed { background: var(--green-glow); color: var(--green); }
  .badge.executed { background: var(--yellow-glow); color: var(--yellow); }
  
  .cmd-cell {
    max-width: 400px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  
  .footer {
    text-align: center;
    margin-top: 2rem;
    padding-top: 1rem;
    border-top: 1px solid var(--border);
    font-size: 0.75rem;
    color: var(--text-dim);
  }
</style>
</head>
<body>

<div class="header">
  <h1>🔒 KM Security Dashboard</h1>
  <div class="period" id="period"></div>
</div>

<div class="stats-grid">
  <div class="stat-card total">
    <div class="number" id="totalCount">-</div>
    <div class="label">전체 이벤트</div>
  </div>
  <div class="stat-card blocked">
    <div class="number" id="blockedCount">-</div>
    <div class="label">차단됨</div>
  </div>
  <div class="stat-card allowed">
    <div class="number" id="allowedCount">-</div>
    <div class="label">허용됨</div>
  </div>
  <div class="stat-card rate">
    <div class="number" id="blockRate">-</div>
    <div class="label">차단율</div>
  </div>
</div>

<div class="charts-row">
  <div class="chart-card">
    <h3>카테고리별 차단 현황</h3>
    <canvas id="categoryChart" height="260"></canvas>
  </div>
  <div class="chart-card">
    <h3>시간대별 활동</h3>
    <canvas id="hourlyChart" height="260"></canvas>
  </div>
</div>

<div class="log-section">
  <h3>최근 차단 이벤트 (최신 20건)</h3>
  <table>
    <thead>
      <tr>
        <th>시간</th>
        <th>상태</th>
        <th>카테고리</th>
        <th>명령어 / 파일</th>
        <th>사용자</th>
      </tr>
    </thead>
    <tbody id="logTableBody">
    </tbody>
  </table>
</div>

<div class="footer">
  KM Security Plugin — 카카오모빌리티 Tech Planning Team<br>
  Generated: <span id="genTime"></span>
</div>

<script>
// ── 데이터 주입 (generate 스크립트가 치환) ──
const DATA = {
HTMLSTART

# 데이터 주입
cat >> "$OUTPUT" << DATAINJECT
  period: "${START_DATE} ~ ${END_DATE}",
  total: ${TOTAL},
  blocked: ${BLOCKED},
  allowed: ${ALLOWED},
  executed: ${EXECUTED},
  categoryStats: ${CATEGORY_STATS},
  recentBlocks: ${RECENT_BLOCKS},
  hourlyStats: ${HOURLY_STATS}
DATAINJECT

cat >> "$OUTPUT" << 'HTMLEND'
};

// ── 렌더링 ──
document.getElementById('period').textContent = DATA.period;
document.getElementById('totalCount').textContent = DATA.total.toLocaleString();
document.getElementById('blockedCount').textContent = DATA.blocked.toLocaleString();
document.getElementById('allowedCount').textContent = DATA.allowed.toLocaleString();

const rate = DATA.total > 0 ? ((DATA.blocked / DATA.total) * 100).toFixed(1) : '0.0';
document.getElementById('blockRate').textContent = rate + '%';
document.getElementById('genTime').textContent = new Date().toLocaleString('ko-KR');

// 카테고리 차트
const catCtx = document.getElementById('categoryChart').getContext('2d');
new Chart(catCtx, {
  type: 'bar',
  data: {
    labels: DATA.categoryStats.map(d => d.category),
    datasets: [{
      label: '차단 횟수',
      data: DATA.categoryStats.map(d => d.count),
      backgroundColor: [
        '#ef4444', '#f97316', '#eab308', '#22c55e', 
        '#3b82f6', '#8b5cf6', '#ec4899', '#06b6d4',
        '#84cc16', '#f43f5e'
      ],
      borderRadius: 6,
      borderSkipped: false,
    }]
  },
  options: {
    responsive: true,
    plugins: {
      legend: { display: false },
    },
    scales: {
      x: {
        ticks: { color: '#64748b', font: { size: 11 } },
        grid: { display: false }
      },
      y: {
        ticks: { color: '#64748b', stepSize: 1 },
        grid: { color: 'rgba(30,41,59,0.5)' }
      }
    }
  }
});

// 시간대 차트
const hourCtx = document.getElementById('hourlyChart').getContext('2d');
const hours = Array.from({length: 24}, (_, i) => String(i).padStart(2, '0'));
const hourMap = {};
DATA.hourlyStats.forEach(h => { hourMap[h.hour] = h; });

new Chart(hourCtx, {
  type: 'line',
  data: {
    labels: hours.map(h => h + ':00'),
    datasets: [
      {
        label: '전체',
        data: hours.map(h => hourMap[h] ? hourMap[h].total : 0),
        borderColor: '#3b82f6',
        backgroundColor: 'rgba(59,130,246,0.1)',
        fill: true,
        tension: 0.4,
        pointRadius: 2,
      },
      {
        label: '차단',
        data: hours.map(h => hourMap[h] ? hourMap[h].blocked : 0),
        borderColor: '#ef4444',
        backgroundColor: 'rgba(239,68,68,0.1)',
        fill: true,
        tension: 0.4,
        pointRadius: 2,
      }
    ]
  },
  options: {
    responsive: true,
    plugins: {
      legend: {
        labels: { color: '#94a3b8', font: { size: 11 } }
      }
    },
    scales: {
      x: {
        ticks: { color: '#64748b', font: { size: 10 }, maxTicksLimit: 12 },
        grid: { display: false }
      },
      y: {
        ticks: { color: '#64748b', stepSize: 1 },
        grid: { color: 'rgba(30,41,59,0.5)' }
      }
    }
  }
});

// 로그 테이블
const tbody = document.getElementById('logTableBody');
DATA.recentBlocks.forEach(log => {
  const tr = document.createElement('tr');
  const time = log.timestamp ? log.timestamp.replace('T', ' ').substring(0, 19) : '-';
  const content = log.command || log.file || '-';
  const statusClass = log.status.toLowerCase();
  
  tr.innerHTML = `
    <td>${time}</td>
    <td><span class="badge ${statusClass}">${log.status}</span></td>
    <td>${log.category || '-'}</td>
    <td class="cmd-cell" title="${content}">${content}</td>
    <td>${log.user || '-'}</td>
  `;
  tbody.appendChild(tr);
});

if (DATA.recentBlocks.length === 0) {
  tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:#64748b;padding:2rem;">차단 이벤트가 없습니다 🎉</td></tr>';
}
</script>
</body>
</html>
HTMLEND

echo "✅ 대시보드 생성 완료: $OUTPUT"

# 브라우저에서 열기 시도
if command -v open &> /dev/null; then
    open "$OUTPUT"
elif command -v xdg-open &> /dev/null; then
    xdg-open "$OUTPUT"
else
    echo "브라우저에서 직접 열어주세요: $OUTPUT"
fi

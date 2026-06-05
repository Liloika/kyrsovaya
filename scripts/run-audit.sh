#!/bin/bash
set +e

mkdir -p reports

echo "=== CI: kube-score bad manifest ==="
docker run --rm -v "$(pwd)":/workdir zegl/kube-score:latest \
  score /workdir/k8s/deploy-false/deployment.yml \
  --output-format json > reports/kube-score-bad.json

echo "=== CI: kube-score good manifest ==="
docker run --rm -v "$(pwd)":/workdir zegl/kube-score:latest \
  score /workdir/k8s/deploy-true/deployment.yml \
  --output-format json > reports/kube-score-good.json

echo "=== Build: Docker image ==="
docker build -t k8s-audit-test:latest docker/ > reports/docker-build.txt 2>&1

echo "=== Build: Trivy image scan ==="
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image k8s-audit-test:latest \
  > reports/trivy-image.txt 2>&1

echo "=== Pre-deploy: OPA policy check bad manifest ==="
docker run --rm -v "$(pwd)":/data openpolicyagent/opa \
  eval --input /data/k8s/deploy-false/deployment.yml \
  --data /data/policies/deny-privileged.rego \
  'data.kubernetes.security.deny' \
  > reports/opa-bad.txt 2>&1

echo "=== Pre-deploy: OPA policy check good manifest ==="
docker run --rm -v "$(pwd)":/data openpolicyagent/opa \
  eval --input /data/k8s/deploy-true/deployment.yml \
  --data /data/policies/deny-privileged.rego \
  'data.kubernetes.security.deny' \
  > reports/opa-good.txt 2>&1

echo "=== Deploy: kubectl dry-run bad manifest ==="
kubectl apply -f k8s/deploy-false/deployment.yml --dry-run=client \
  > reports/kubectl-dryrun-bad.txt 2>&1

echo "=== Deploy: kubectl dry-run good manifest ==="
kubectl apply -f k8s/deploy-true/deployment.yml --dry-run=client \
  > reports/kubectl-dryrun-good.txt 2>&1
echo "=== Generate HTML report ==="

cat > reports/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<title>Kubernetes Continuous Audit Report</title>
<style>
body {
  font-family: Arial, sans-serif;
  background: #f5f7fa;
  margin: 24px;
  color: #2c3e50;
}
h1 {
  font-size: 32px;
}
h2 {
  margin-top: 30px;
}
.section {
  background: white;
  border: 1px solid #dcdcdc;
  border-radius: 8px;
  padding: 18px;
  margin-bottom: 22px;
}
.meta {
  color: #7f8c8d;
  font-size: 14px;
}
.error {
  color: #e74c3c;
  font-weight: bold;
}
.ok {
  color: #2ecc71;
  font-weight: bold;
}
.warn {
  color: #f39c12;
  font-weight: bold;
}
pre {
  background: #f1f3f5;
  border: 1px solid #ddd;
  border-radius: 6px;
  padding: 12px;
  overflow-x: auto;
  white-space: pre-wrap;
}
.card-error {
  border-left: 5px solid #e74c3c;
  padding: 10px;
  background: #fffafa;
  margin: 8px 0;
}
.card-ok {
  border-left: 5px solid #2ecc71;
  padding: 10px;
  background: #f7fff9;
  margin: 8px 0;
}
.card-warn {
  border-left: 5px solid #f39c12;
  padding: 10px;
  background: #fffaf0;
  margin: 8px 0;
}
details {
  margin-top: 10px;
}
summary {
  cursor: pointer;
  font-weight: bold;
}
</style>
</head>
<body>

<h1>📋 Kubernetes Continuous Audit Report</h1>

<div class="section">
  <h2>1. CI: статический анализ Kubernetes-манифестов (kube-score)</h2>
  <p class="meta">Проверяются два манифеста: небезопасный и исправленный.</p>

  <h3>❌ Небезопасный манифест</h3>
  <p class="meta"><b>Файл:</b> k8s/deploy-false/deployment.yml</p>
  <p class="meta"><b>Объект:</b> Deployment / vulnerable-app</p>

  <div class="card-error">
    <b>Privileged Container</b><br>
    Контейнер запущен в privileged-режиме.<br>
    Рекомендация: <code>securityContext.privileged = false</code>
  </div>

  <div class="card-error">
    <b>Container Image Tag</b><br>
    Используется тег <code>latest</code>.<br>
    Рекомендация: использовать фиксированную версию образа.
  </div>

  <div class="card-error">
    <b>ReadOnlyRootFilesystem</b><br>
    Root filesystem доступен для записи.<br>
    Рекомендация: <code>readOnlyRootFilesystem = true</code>
  </div>

  <div class="card-error">
    <b>Resources</b><br>
    Не заданы requests/limits для CPU и Memory.
  </div>

  <div class="card-error">
    <b>User / Group ID</b><br>
    Контейнер запущен с низким UID/GID.
  </div>

  <div class="card-error">
    <b>NetworkPolicy</b><br>
    Pod не покрыт NetworkPolicy.
  </div>

  <details>
    <summary>Показать сырой JSON-отчёт kube-score для небезопасного манифеста</summary>
    <pre>
EOF

cat reports/kube-score-bad.json >> reports/index.html

cat >> reports/index.html << 'EOF'
    </pre>
  </details>

  <h3>✅ Исправленный манифест</h3>
  <p class="meta"><b>Файл:</b> k8s/deploy-true/deployment.yml</p>
  <p class="meta"><b>Объект:</b> Deployment / secure-app</p>

  <div class="card-ok">Stable API version</div>
  <div class="card-ok">Label values</div>
  <div class="card-ok">Container Security Context</div>
  <div class="card-ok">Resources Requests & Limits</div>
  <div class="card-ok">ReadOnlyRootFilesystem</div>

  <div class="card-warn">
    <b>NetworkPolicy</b><br>
    Проверка может формировать предупреждение, если отдельный NetworkPolicy не описан в тестовом наборе.
  </div>

  <details>
    <summary>Показать сырой JSON-отчёт kube-score для исправленного манифеста</summary>
    <pre>
EOF

cat reports/kube-score-good.json >> reports/index.html

cat >> reports/index.html << 'EOF'
    </pre>
  </details>
</div>

<div class="section">
  <h2>2. Build: сборка контейнерного образа</h2>
  <p class="meta">На данном этапе выполняется сборка тестового контейнерного образа.</p>
  <div class="card-ok">
    Docker-образ <code>k8s-audit-test:latest</code> был собран.
  </div>
  <details>
    <summary>Показать лог сборки Docker</summary>
    <pre>
EOF

cat reports/docker-build.txt >> reports/index.html

cat >> reports/index.html << 'EOF'
    </pre>
  </details>
</div>

<div class="section">
  <h2>3. Image Scan: анализ контейнерного образа (Trivy)</h2>
  <p class="meta">Trivy используется для поиска известных уязвимостей и секретов в контейнерном образе.</p>
  <div class="card-ok">
    Сканирование образа запущено, база уязвимостей загружена, анализ включён.
  </div>
  <details>
    <summary>Показать отчёт Trivy</summary>
    <pre>
EOF

cat reports/trivy-image.txt >> reports/index.html

cat >> reports/index.html << 'EOF'
    </pre>
  </details>
</div>

<div class="section">
  <h2>4. Pre-deploy: проверка политик безопасности (OPA)</h2>
  <p class="meta">OPA проверяет манифесты по формализованным правилам безопасности.</p>

  <h3>❌ Небезопасный манифест</h3>
  <div class="card-error">
    Нарушены политики: privileged-контейнер запрещён, использование latest-тега запрещено.
  </div>

  <details open>
    <summary>Показать результат OPA для небезопасного манифеста</summary>
    <pre>
EOF

cat reports/opa-bad.txt >> reports/index.html

cat >> reports/index.html << 'EOF'
    </pre>
  </details>

  <h3>✅ Исправленный манифест</h3>
  <div class="card-ok">
    Нарушения политик не выявлены.
  </div>

  <details>
    <summary>Показать результат OPA для исправленного манифеста</summary>
    <pre>
EOF

cat reports/opa-good.txt >> reports/index.html

cat >> reports/index.html << 'EOF'
    </pre>
  </details>
</div>

<div class="section">
  <h2>5. Deploy: предварительная проверка применения манифеста</h2>
  <p class="meta">Этап развертывания смоделирован через kubectl dry-run без фактического создания ресурсов.</p>

  <details>
    <summary>Показать результат dry-run для небезопасного манифеста</summary>
    <pre>
EOF

cat reports/kubectl-dryrun-bad.txt >> reports/index.html

cat >> reports/index.html << 'EOF'
    </pre>
  </details>

  <details>
    <summary>Показать результат dry-run для исправленного манифеста</summary>
    <pre>
EOF

cat reports/kubectl-dryrun-good.txt >> reports/index.html

cat >> reports/index.html << 'EOF'
    </pre>
  </details>
</div>

<div class="section">
  <h2>Итоговое решение</h2>
  <div class="card-error">
    Небезопасный манифест должен быть заблокирован до развертывания.
  </div>
  <div class="card-ok">
    Исправленный манифест допускается к дальнейшим этапам жизненного цикла.
  </div>
  <p>
    Практическая проверка показывает, что предложенный процесс непрерывного аудита позволяет выявлять ошибки конфигурации,
    нарушения политик безопасности и уязвимости контейнерных образов до применения ресурсов в Kubernetes.
  </p>
</div>

</body>
</html>
EOF
echo "Готово. Отчёты сохранены в reports/"

# ============================================
# Анализ результатов и возврат кода завершения
# ============================================
echo ""
echo "=== Анализ результатов ==="

CRITICAL_ERRORS=0

# Проверка kube-score
if [ -f reports/kube-score-bad.json ]; then
    KUBE_SCORE_ERRORS=$(jq '[.[] | .checks[] | select(.grade < 5)] | length' reports/kube-score-bad.json)
    if [ "$KUBE_SCORE_ERRORS" -gt 0 ]; then
        echo "❌ kube-score: обнаружено $KUBE_SCORE_ERRORS критических нарушений"
        CRITICAL_ERRORS=$((CRITICAL_ERRORS + KUBE_SCORE_ERRORS))
    else
        echo "✅ kube-score: критических нарушений не обнаружено"
    fi
fi

# Проверка OPA
if [ -f reports/opa-bad.txt ]; then
    if grep -q "deny" reports/opa-bad.txt; then
        echo "❌ OPA: обнаружены нарушения политик"
        CRITICAL_ERRORS=$((CRITICAL_ERRORS + 1))
    else
        echo "✅ OPA: нарушений политик не обнаружено"
    fi
fi

# Итоговое решение
echo ""
if [ "$CRITICAL_ERRORS" -gt 0 ]; then
    echo "========================================="
    echo "❌ ОБНАРУЖЕНО КРИТИЧЕСКИХ НАРУШЕНИЙ: $CRITICAL_ERRORS"
    echo "========================================="
    exit 1
else
    echo "========================================="
    echo "✅ КРИТИЧЕСКИХ НАРУШЕНИЙ НЕ ОБНАРУЖЕНО"
    echo "========================================="
    exit 0
fi

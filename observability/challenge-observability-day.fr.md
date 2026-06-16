# Challenge — Construis ta stack d'observabilité (journée pratique complète)

> **Version française du `challenge-observability-day.md`.** Les README des labs liés
> restent en anglais — réfère-t'y pour les commandes exactes.
>
> **Format** : en binômes (2). Si l'effectif est impair, un seul trinôme (3).
> Vous êtes un duo dev + plateforme : à la fin de la journée, votre app tourne sur un
> cluster qui la surveille, et vous présentez le tout en live. Tout ce dont vous avez
> besoin est dans les README des labs liés ci-dessous — avancez à votre rythme.

---

## La mission

Une entreprise fictive s'apprête à déployer un service sur Kubernetes et avance à
l'aveugle : pas de métriques, pas de dashboards, pas d'alertes. **Le job de votre duo :
livrer l'app ET les yeux qui la surveillent.**

Vous séparez le travail en deux rôles :

| Rôle | Responsable | Ce qu'il construit | Lab principal |
|------|-------------|--------------------|---------------|
| 🛠️ **L'App** | une personne | Un service instrumenté : métriques RED, logs JSON structurés, `/metrics` exposé | [`observability/lab03-instrumenting-services`](./lab03-instrumenting-services/README.md) |
| 📡 **La Stack** | l'autre personne | La plateforme d'observabilité sur kind : Prometheus + Grafana + Alertmanager, scraping + dashboards + alertes | [`k8s-operations/lab06-monitoring-stack`](../k8s-operations/lab06-monitoring-stack/README.md) |

Le cœur de la journée : **les faire se rencontrer.** La Stack doit scraper L'App,
afficher ses métriques dans un dashboard, et alerter sur ses erreurs. Cette passation —
un dev livre un service, la plateforme le rend observable — c'est exactement ce qui se
passe dans une vraie équipe.

> **Trinôme ?** La 3ᵉ personne prend une **track de spécialisation** (logs ou traces, voir
> Partie 3) et la démarre dès que L'App tourne sur La Stack — ou fait du pair-programming
> avec celui qui est en retard.

À la fin de la journée vous aurez :

1. Une app instrumentée qui tourne sur un cluster.
2. Une stack de métriques qui la scrape, avec un dashboard custom et une alerte qui se
   déclenche **sur votre app**.
3. (Si le temps / trinôme) un pilier de plus — logs ou traces.
4. Une démo de 5-7 min où **vous deux** présentez votre moitié et la passation entre elles.

Vous travaillez **en autonomie** à partir des README des labs. L'instructeur circule pour
vous débloquer — levez la main à chaque checkpoint, ou dès que vous bloquez plus de 10 minutes.

---

## Règles du jeu

- **Séparez, mais ne vous isolez pas.** Chacun possède sa moitié, mais synchronisez-vous
  souvent — vos deux moitiés doivent se connecter. Quand l'un bloque, mettez-vous à deux
  jusqu'au déblocage.
- **Un cluster par binôme.** La personne Stack le possède ; la personne App y déploie au
  moment de l'intégration.
- **Bloqué·e > 10 min ?** D'abord la section Validation du README, puis ton binôme, puis lève la main.
- **Fini en avance ?** Il y a toujours plus — voir [Pour aller plus loin](#pour-aller-plus-loin). Personne ne reste les bras croisés.

---

## Partie 1 — Construire en parallèle · ~2h15

Les deux rôles travaillent en même temps. Vous ne vous bloquez pas — synchro au Checkpoint 1.

### 🛠️ L'App — `lab03-instrumenting-services`
1. Lis le starter Flask et ses cinq marqueurs `# TODO`.
2. Ajoute le **Counter** + l'**Histogram** (métriques RED), expose **`/metrics`**.
3. Bascule les logs en **JSON structuré** avec un `request_id`.
4. Build l'image et `kind load`.
> Tu peux écrire et builder tout ça **avant** que le cluster soit prêt — tu n'as besoin de
> La Stack qu'au moment du déploiement. N'attends pas ton binôme pour démarrer.

### 📡 La Stack — `lab06-monitoring-stack`
1. Installe `kube-prometheus-stack` via Helm.
2. Accède aux UIs Grafana, Prometheus et Alertmanager.
3. Utilise l'**app d'exemple** du lab pour vérifier le scraping de bout en bout : ServiceMonitor → cible **UP** → PromQL qui retourne des données.
4. Construis un premier **dashboard custom** (Rate / Errors / Duration) sur l'app d'exemple.
> Faire scraper l'app d'exemple prouve que ta moitié fonctionne **avant** l'arrivée de
> l'app de ton binôme. Tu pointeras la même machinerie sur la vraie app en Partie 2.

### ✅ Checkpoint 1 — « Stack debout, App buildée »
Levez la main quand : **La Stack** a Grafana ouvert + une cible d'exemple **UP** dans
Prometheus, **et** L'App a son image instrumentée buildée et `kind load`ée. (Rappel : c'est
le label `release: monitoring` qui fait découvrir un ServiceMonitor par l'opérateur.)

---

## Partie 2 — Intégration : les faire se rencontrer · ~1h

C'est le cœur de la journée. Faites-le **à deux.**

1. **Déployez** L'App sur le cluster de La Stack (`kubectl apply` des manifests de L'App).
2. **Faites-la découvrir** — le Service + le ServiceMonitor de L'App (avec le label
   `release: monitoring`) doivent faire apparaître la cible de L'App en **UP** dans
   Prometheus → Status → Targets.
3. **Mettez-la en dashboard** — la personne Stack construit (ou retargette) un dashboard
   montrant les métriques RED propres à L'App : taux de requêtes, ratio d'erreurs, latence p99.
4. **Alertez dessus** — une PrometheusRule qui se déclenche sur le taux d'erreurs de L'App.
   Générez du trafic / des erreurs contre L'App et regardez-la passer `Pending → Firing`.

### ✅ Checkpoint 2 — « L'App est observée »
Levez la main quand : les métriques de **votre propre app** sont en live dans un dashboard
Grafana **et** une alerte est **Firing** sur le taux d'erreurs de votre app. C'est le minimum
requis pour la démo.

---

## Partie 3 — Ajouter un pilier (job du trinôme, ou à deux si le temps) · ~45-60 min

Ajoutez **un** pilier supplémentaire. Pour un trinôme, c'est la track de la 3ᵉ personne dès le début.

| Track | Lab | Vous saurez… |
|-------|-----|--------------|
| 🪵 **Logs** | [`k8s-operations/lab07-loki-logs`](../k8s-operations/lab07-loki-logs/README.md) | Centraliser les logs avec Loki, requêter en LogQL depuis Grafana, sauter d'un pic de métrique vers les lignes de log de L'App qui l'ont causé |
| 🔍 **Traces** | [`observability/lab02-traces`](./lab02-traces/README.md) | Installer Grafana Tempo, déployer une app instrumentée OTel, lire un arbre de trace distribuée, requêter en TraceQL |

> **Comment choisir** : Logs s'enchaîne le plus naturellement avec votre app instrumentée
> (vous émettez déjà du JSON structuré — il ne reste qu'à le centraliser). Traces est le plus
> visuel pour la démo.

### ✅ Checkpoint 3 — « 3ᵉ pilier fonctionnel »
Levez la main quand votre track atteint l'étape de Validation principale de son README
(les logs de votre App requêtables dans Grafana, ou un arbre de trace visible dans Tempo).

---

## Partie 4 — Démo · les ~75 dernières min

Chaque duo présente en live. **5-7 minutes**, puis 2-3 minutes de questions de la salle.
Pas de slides — pilotez les UIs en direct. **Vous parlez tous les deux** : la personne App
présente la moitié app, la personne Stack présente la moitié plateforme, et ensemble vous
montrez la passation.

### Ce qu'il faut montrer
1. **L'App** (responsable App) — l'endpoint instrumenté, les métriques qu'il expose, les logs structurés.
2. **La Stack** (responsable Stack) — ce qui tourne (`kubectl get pods -n monitoring`), la page Targets qui prouve que votre app est scrapée.
3. **Le dashboard** — déroulez un panel, expliquez le PromQL derrière.
4. **Une alerte qui se déclenche** — sur votre app, montrez-la dans Prometheus/Alertmanager, expliquez la règle.
5. **(Si fait) le 3ᵉ pilier** — une requête LogQL sur les logs de votre app, ou un arbre de trace.
6. **Un truc qui a cassé** — ce qui a foiré au moment de la passation et comment vous l'avez réparé.
   (C'est souvent les 60 secondes les plus utiles de la démo.)

### Grille d'évaluation de la démo

| Critère | Ce que « bien » veut dire |
|---------|---------------------------|
| **Ça marche** | App qui tourne, scrapée par La Stack, UIs accessibles, pas de bla-bla |
| **La passation** | Vous savez expliquer comment La Stack découvre et scrape L'App (le ServiceMonitor + le label) |
| **Compréhension** | Chaque responsable explique le *pourquoi*, pas juste le *quoi* — que calcule ce PromQL ? pourquoi ce type de métrique ? |
| **Alerting** | Une alerte qui se déclenche sur L'App pour une vraie condition, avec un seuil sensé |
| **Travail d'équipe** | Les deux parlent, chacun possède sa moitié, personne n'est passager |
| **Communication** | Clair, honnête (y compris ce qui a cassé), dans le temps imparti |

---

## Pour aller plus loin

Intégration finie avec du temps devant vous ? Au choix :

- **Ajoutez l'autre pilier** — faites logs ET traces.
- **Corrélation des trois piliers** — câblez le `trace_id` pour pouvoir cliquer d'un exemplar
  de métrique → une trace → ses lignes de log, le tout pour votre propre app. La démo graal.
- **Une vraie métrique métier** — ajoutez un compteur applicatif (ex. `orders_placed_total`)
  et mettez-le en dashboard à côté des métriques RED.
- **La section « Going Further » de chaque lab** — stockage long terme avec Thanos, tail-sampling, …
- **Cassez les stacks des autres** — échangez de cluster avec un autre duo, introduisez une
  panne (scale L'App à 0, push une mauvaise image), et voyez quelles alertes attrapent ça en premier.

---

## Aide-mémoire

```bash
# Cluster en bonne santé ?
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed   # devrait être ~vide

# La stack de monitoring
kubectl get pods -n monitoring

# Charger l'image de L'App dans kind (responsable App, au moment de l'intégration)
docker build -t <app>:dev .
kind load docker-image <app>:dev

# Atteindre les UIs (une par terminal, ou en arrière-plan avec &)
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

Login Grafana : `admin` / `admin` (défaut du lab).

Le piège n°1 de l'intégration : un ServiceMonitor sans le label `release: monitoring` est
ignoré silencieusement par l'opérateur — la cible de votre app n'apparaît jamais. Vérifiez ça en premier.

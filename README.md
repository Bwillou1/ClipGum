<p align="center">
  <img src="docs/app-icon.png" width="128" height="128" alt="ClipGum Logo" style="border-radius: 28px; box-shadow: 0 10px 30px rgba(0,0,0,0.3);">
</p>

<h1 align="center">ClipGum</h1>

<p align="center">
  <strong>Le presse-papiers intelligent, ultra-privé et 100% hors-ligne pour macOS.</strong><br>
  <em>Nettoyage automatique des URLs, protection des tokens développeurs, menu radial sous le curseur et IA locale Bonsai 4B MLX.</em>
</p>

<p align="center">
  <a href="https://github.com/Bwillou1/ClipGum/actions"><img src="https://img.shields.io/github/actions/workflow/status/Bwillou1/ClipGum/ci.yml?branch=main&style=flat-square&label=CI%20Build" alt="CI Status"></a>
  <a href="https://github.com/Bwillou1/ClipGum/releases"><img src="https://img.shields.io/github/v/release/Bwillou1/ClipGum?include_prereleases&style=flat-square&color=pink&label=Pre-Release" alt="Latest Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple_Silicon-M1%2FM2%2FM3%2FM4-orange?style=flat-square" alt="Apple Silicon">
  <a href="https://bwillou1.github.io/ClipGum/"><img src="https://img.shields.io/badge/Showcase-Site_Web-purple?style=flat-square" alt="Site Web"></a>
</p>

---

## 🌟 Pourquoi ClipGum ?

ClipGum transforme votre presse-papiers macOS en un outil de productivité puissant et intraitable sur la confidentialité. Contrairement aux gestionnaires de presse-papiers classiques qui espionnent ou stockent tout votre historique dans le cloud, **ClipGum opère à 100% en local dans la mémoire vive de votre Mac.**

* ⚡ **Nettoyage automatique d'URLs en arrière-plan** : Copiez un lien, tous les mouchards publicitaires (`utm_*`, `fbclid`, `gclid`, etc.) sont purgés instantanément sans demander de confirmation.
* 🔑 **Mode Développeur (Préservation des Tokens)** : Vos clés API (`ghp_...`, `sk-...`, AWS) ne sont jamais détruites ni remplacées par inadvertance lors de la copie.
* 🎯 **Analyse d'Intention & Probabilité du Besoin** : Comprend automatiquement la nature de vos données (JSON, code, tableau, URL traquée, texte brut) et prédit la probabilité du besoin (ex: 98%).
* 🎛️ **Roue Radiale sous le Curseur (`⌃X`)** : Entoure votre souris d'un menu circulaire futuriste pour sélectionner l'action souhaitée d'un geste.
* 🧽 **Palette HUD Express (`⌃Z`)** : Nettoyage et collage instantanés sous votre curseur.
* 🧠 **IA Locale Bonsai 4B MLX (1-Clic)** : Téléchargez et exécutez le modèle 2-bit ternaire de Prism ML directement sur Apple Silicon (Metal) en toute légalité sous licence Apache 2.0.

---

## 🚀 Installation

### Option 1 : Via Homebrew (Recommandé)

Vous pouvez installer ClipGum en une seule ligne de commande via Homebrew :

```bash
# Installation directe via la formule Cask de ClipGum
brew install --cask https://raw.githubusercontent.com/Bwillou1/ClipGum/main/Casks/clipgum.rb
```

Ou en ajoutant le tap officiel :

```bash
brew tap Bwillou1/clipgum
brew install --cask clipgum
```

Pour mettre à jour ClipGum via Homebrew à l'avenir :
```bash
brew upgrade --cask clipgum
```

---

### Option 2 : Téléchargement Direct du DMG

1. Rendez-vous sur la page des [Dernières Releases GitHub](https://github.com/Bwillou1/ClipGum/releases).
2. Téléchargez le fichier `ClipGum-x.x.x.dmg`.
3. Ouvrez le DMG et glissez `ClipGum.app` dans votre dossier `/Applications`.
4. Lancez ClipGum depuis Spotlight ou votre Launchpad !

> [!NOTE]  
> Comme ClipGum est distribué en open-source hors du Mac App Store, macOS peut afficher un avertissement au premier lancement. Allez dans *Réglages Système → Confidentialité et Sécurité* puis cliquez sur **Ouvrir quand même**.

---

## ⌨️ Raccourcis Clavier Globaux

| Raccourci | Fonction | Description |
| :--- | :--- | :--- |
| **`Control-Z`** (`⌃Z`) | **Palette HUD / Smart Paste** | Ouvre le panneau d'inspection complet et de nettoyage sous le curseur. *(Secondaire : `⌘⇧V`)* |
| **`Control-X`** (`⌃X`) | **Roue Radiale Souris** | Fait apparaître la roue circulaire d'actions directement autour du curseur de votre souris. *(Secondaire : `⌘⌥V`)* |
| **`⌘L`** | **Inspecteur & Logs en Direct** | Ouvre le journal de bord montrant les URLs nettoyées, les secrets détectés et la latence. |
| **`⌘,`** | **Réglages & Inférence** | Permet de configurer l'IA Bonsai 4B, les règles de nettoyage et les serveurs locaux. |

---

## 🧠 Modèle d'IA Local Bonsai 4B MLX (Téléchargement en 1-Clic)

ClipGum intègre le support natif du modèle **Bonsai Image Ternary 4B MLX** (`prism-ml/bonsai-image-ternary-4B-mlx-2bit`), développé par Prism ML :

* **Technologie On-Device** : Optimisé pour le moteur Metal des puces Apple Silicon (M1/M2/M3/M4) avec une quantification 2-bit ternaire ultra-légère.
* **Licence Apache 2.0** : Conforme et légal, basé sur FLUX.2 Klein 4B et l'encodeur de texte Qwen3-4B.
* **Téléchargement en 1-Clic dans l'application** :
  1. Ouvrez les **Réglages** (`⌘,`) → onglet **Modèles**.
  2. Cochez la case d'acceptation de la licence Apache 2.0.
  3. Cliquez sur **« Télécharger Bonsai 4B en 1-Clic »**.
  4. L'application télécharge les configurations et tenseurs en tâche de fond avec une jauge de progression en temps réel, sans jamais geler l'interface.
* **Support Hugging Face & Localhost** : Vous pouvez également charger n'importe quel dépôt Hugging Face ou vous connecter à vos serveurs locaux **Ollama** (`http://localhost:11434/v1`) et **LM Studio**.

---

## 🎯 Détection d'Intention & Probabilité du Besoin

À chaque copie, le moteur heuristique et IA de ClipGum calcule instantanément l'intention dominante et le pourcentage de certitude :

* 🔗 **Nettoyage d'URL (Probabilité : 99%)** : Détecte les paramètres `utm_source`, `utm_campaign`, `fbclid`, `gclid` et les supprime.
* 🔑 **Token Développeur (Probabilité : 98%)** : Détecte un GitHub PAT (`ghp_...`), une clé OpenAI (`sk-...`) ou AWS et la préserve en clair.
* 📐 **Formatage JSON (Probabilité : 97%)** : Détecte un JSON brut ou minifié et propose l'indentation ou la conversion en interfaces TypeScript.
* 📊 **Conversion Tabulaire (Probabilité : 96%)** : Détecte du CSV ou TSV et le convertit en tableau Markdown aligné.
* 📄 **Réparation PDF (Probabilité : 93%)** : Détecte les retours à la ligne intempestifs et césures de mots issues de copier-coller de PDF.
* 🛡️ **Anonymisation PII (Probabilité : 94%)** : Masque les adresses IP internes et données nominatives sensibles.

---

## 🛡️ Manifeste de Sécurité & Confidentialité

ClipGum a été conçu selon des principes cryptographiques et d'isolation stricts :

1. **Zéro Serveur / Zéro Cloud** : ClipGum ne possède aucun serveur backend. Vos textes copiés ne transitent sur aucun réseau extérieur.
2. **Aucun Historique Persistant** : Vos données restent uniquement dans la mémoire vive volatile le temps de l'opération choisie.
3. **Sandbox macOS Stricte** : Entitlements réseau restreints uniquement aux téléchargements explicitement ordonnés par l'utilisateur (mises à jour signées Sparkle et modèles IA).
4. **Audit en Direct** : Appuyez sur `⌘L` à tout moment pour visualiser exactement ce que ClipGum a nettoyé ou préservé.

---

## 🛠️ Compilation depuis les Sources

Pour les développeurs souhaitant contribuer ou auditer le code :

```bash
# Cloner le dépôt
git clone https://github.com/Bwillou1/ClipGum.git
cd ClipGum

# Compiler les tests unitaires
swift test

# Compiler l'application macOS
./scripts/package_app.sh

# Lancer la version compilée
open build/ClipGum.app
```

---

## 🌐 Site Vitrine & Documentation

* **Site Officiel (Anglais)** : [https://bwillou1.github.io/ClipGum/](https://bwillou1.github.io/ClipGum/)
* **Version Française** : [https://bwillou1.github.io/ClipGum/fr.html](https://bwillou1.github.io/ClipGum/fr.html)
* **Portail Sécurité & Licences** : [https://bwillou1.github.io/ClipGum/security.html](https://bwillou1.github.io/ClipGum/security.html)

---

## 📄 Licence

Ce projet est sous licence **Apache 2.0**. Consultez le fichier [`LICENSE`](LICENSE) pour plus de détails.  
*Modèle Bonsai 4B par Prism ML, Inc. sous licence Apache 2.0.*

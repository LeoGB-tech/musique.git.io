# Ma Musique

Lecteur iOS (SwiftUI) qui lit un dossier iCloud Drive et télécharge/actualise automatiquement les musiques.

## Compiler l'IPA
1. Crée un dépôt GitHub et pousse ce dossier (branche `main`).
2. Onglet Actions > "Build IPA" > télécharge l'artefact `MaMusique-ipa`.
3. L'IPA n'est pas signé : signe-le avec AltStore / Sideloadly (Apple ID gratuit, valable 7 jours)
   ou avec un compte Apple Developer + TestFlight (99 €/an, recommandé).

## Envoyer la musique
- Sur icloud.com (compte du grand-père) > iCloud Drive > crée un dossier "Musique" et dépose les fichiers.
  Ou active iCloud Drive sur ton ordinateur et dépose-les dans le dossier synchronisé.
- Sur son iPhone : ouvre l'app > "Choisir le dossier" > sélectionne "Musique".
- À chaque ouverture (ou tirer vers le bas), l'app détecte les nouveaux fichiers et les télécharge.

Nécessite iOS 17+.

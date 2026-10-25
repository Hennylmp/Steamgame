# Rumble Table (Arbeitstitel)

3D-Brett-Partyspiel für bis zu 10 Spieler, gebaut mit Godot 4. Ihr seid Aufzieh-Spielfiguren auf einem riesigen Spielbrett, sammelt Kronen, sabotiert euch gegenseitig und kämpft zwischendurch in Minigames.

Das komplette Spielkonzept steht im [Game-Design-Dokument](https://claude.ai/artifact/USeFNFKhRZqLN9sJQZJ1LS).

## Spiel starten

1. Godot 4.4 oder neuer herunterladen: [godotengine.org/download](https://godotengine.org/download) (die normale Version, nicht ".NET").
2. Dieses Repository herunterladen: auf GitHub oben auf **Code** und dann **Download ZIP** klicken, entpacken.
3. Godot starten, auf **Importieren** klicken und die Datei `project.godot` aus dem entpackten Ordner auswählen.
4. Im Editor oben rechts auf den Play-Knopf klicken (oder **F5** drücken).

## Steuerung

**Auf dem Spielbrett (Planungsphase, 15 Sekunden):**

| Taste | Aktion |
| --- | --- |
| 1 / 2 / 3 | Würfel wählen: Standard 1–6, Sicher 2–4, Risiko 0–10 |
| Q / E | An Kreuzungen: Hauptweg oder Zocker-Abkürzung |
| T | Falle auf dem eigenen Feld legen (wenn du eine hast) |
| Enter | Fertig |

**Glücksrad (Zocker-Feld):** J = zocken, N = lieber nicht.

**Minigame "Schmelzende Scholle":** WASD oder Pfeiltasten laufen, Leertaste rempeln. Als Geist knackst du mit der Leertaste Eisplatten an. Controller: linker Stick und A.

## Was im Prototyp drin ist

- Spielbrett mit 32 Feldern: Ring mit 24 Feldern plus zwei Zocker-Abkürzungen voller Glücksfelder
- Alle 10 Spieler planen gleichzeitig und laufen gleichzeitig (du plus 9 Bots)
- Münzen, Kronen-Shop (40 Münzen, wandert nach jedem Kauf), verdeckte Fallen, Ereignisfelder, Rempeln bei gleichem Zielfeld
- Glücksrad: 10 Münzen Einsatz, dann dreifach zurück, eine Krone, eine Niete oder Absturz (halbe Münzen weg, zurück zum Start)
- Minigame "Schmelzende Scholle" mit Geister-Modus
- 12 Runden, danach Rangliste

Grafik ist absichtlich nur Platzhalter. Der Prototyp soll zeigen, ob sich der Spielablauf gut anfühlt.

## Projektaufbau

| Datei | Inhalt |
| --- | --- |
| `scripts/game.gd` | Spielzustand und Regeln (Spieler, Münzen, Würfel, Belohnungen) |
| `scripts/main.gd` | Rundenablauf, Planung, Glücksrad, Anzeige |
| `scripts/board.gd` | Spielbrett, Bewegung, Feld-Effekte, Fallen, Shop |
| `scripts/figure.gd` | Platzhalter-Spielfigur |
| `scripts/minigames/ice_floe.gd` | Minigame "Schmelzende Scholle" |

## Automatischer Test

Ein komplettes Spiel nur mit Bots, ohne Fenster (z. B. 3 Runden):

```
godot --headless --fixed-fps 60 -- --autotest --rounds=3
```

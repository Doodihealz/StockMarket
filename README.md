# 🪙 StockMarket System

This script introduces a dynamic, in-game stock market system to World of Warcraft (AzerothCore-based servers). Players can invest gold via a designated NPC (`Stock Broker`, entry ID `90001`) and watch their investments grow or shrink over time based on random market events.

## 📦 Requirements

- **AzerothCore or TrinityCore** with the **Eluna Engine** enabled.
- A database supporting `character_stockmarket` and `character_stockmarket_log` (see installation SQL).

## ✨ Features

- 🧑‍💼 **Stock Broker NPC (Entry ID: 90001)**
  - Accepts deposits and withdrawals (minimum 1g deposit, no penalty on withdrawal).
  - Handles interactions via gossip menu.
  - Tracks each character's investments individually.

- 🧮 **Stock Investment Logic**
  - Each player can invest gold.
  - Funds are stored in `character_stockmarket`.
  - Gains/losses are recorded in `character_stockmarket_log`.

- ⏱ **Automated Market Events**
  - Randomized market events occur every **15 to 30 minutes**.
  - Events can be positive or negative, with a mild bias toward positive.
  - Events affect **all players’ investments proportionally**.
  - Event history logged with percentage change and message.

- 💬 **Global Announcements**
  - Time until next event is announced globally every 10 minutes.
  - Players see ETA on login.
  - Events broadcast server-wide with color-coded summaries.

- 🧹 **Log Cleanup**
  - Logs older than 30 days are automatically cleaned once every 24 hours.

- 🧪 **Manual GM Controls**
  - `.stockevent`: GM-only command to manually trigger a market event.

- 🧾 **Player Commands**
  - `.stockdata`: Shows player’s investment balance (5-minute cooldown).
  - `.stockhelp`: Lists all available stock commands.
  - `.stocktimer`: Shows time until the next scheduled event.

## 🛠 Installation

1. Copy the Lua scripts into your server's Lua scripts directory:

   - `StockEvents.lua`
   - `Stockbroker.lua`

2. Execute the provided SQL files:

   - `Stockmarketcharacter.sql` — on the **characters** database.
   - `Stockmarketevents.sql` — on the **world** database.
   - `StockBroker.sql` — on the **world** database.

   > NPC uses Entry ID `90001` and Display ID `27822`. If you use a different entry, update it in the Lua file.

3. Restart the server. The stock market will begin operating automatically.

## 📜 Commands

| Command           | Access     | Description                                      |
|-------------------|------------|--------------------------------------------------|
| `.stockdata`      | Player     | View your current invested gold (5m cooldown).   |
| `.stocktimer`     | Player     | See when the next stock market event is.         |
| `.stockhelp`      | Player     | Show all available stock-related commands.       |
| `.stockevent`     | GM Only    | Trigger a random market event manually.          |

## 🧠 Technical Notes

- All currency is stored in copper (1g = 10,000).
- Player funds are tracked per **character**, not account.
- Color codes used in chat are stripped from server logs for cleanliness.
- Market events use weighted randomness with configurable rarity and type bias.
- All transactions are logged with before/after values, deltas, and descriptions.

## ⚠️ Caution

This script is provided **AS IS**. Limited support is available for unmodified versions only. If you make changes and encounter issues, you're expected to debug them independently.

## 🙏 Credits

Developed by:  
**Doodihealz / Corey**

Thanks to the WoW modding community for your help and support.

---

Enjoy gaining (or losing) money!

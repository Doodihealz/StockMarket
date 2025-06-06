StockMarket System
==================================

This script introduces a dynamic, in-game stock market system to World of Warcraft (AzerothCore-based servers). Players can invest gold via a designated NPC ("Stock Broker", entry ID 90001) and watch their investments grow or shrink over time based on random market events.

Requirements
------------

- **AzerothCore / TrinityCore with Eluna Engine enabled**  
  This script requires the Eluna Lua engine to function. Ensure Eluna is properly installed and configured on your server.

Features
--------

- NPC Stock Broker (entry 90001) handles deposits and withdrawals without penalties.
- Automated market events occur every 15–60 minutes, adjusting investment values.
- Events can be positive or negative, with a slight bias toward positive growth.
- All changes are recorded in `character_stockmarket_log` in the `acore_characters` database.
- Individual investment tracking per character (not account-wide).
- Logs older than 30 days are automatically deleted every 24 hours.
- Manual event triggering via `.stockevent` GM command.
- Check how much is in your account with the .stockdata command. Has a 5 minute cooldown between uses.
- Comedic, lore-themed events included for extra fun.

Installation
------------

1. Place the following Lua scripts in your server's Lua scripts folder:
   - `StockEvents.lua`
   - `Stockbroker.lua`

2. Execute the following SQL files:
   - `Stockmarketcharacter.sql` → Run on the **characters database**
   - `Stockmarketevents.sql` → Run on the **world database**
   - `StockBroker.sql` → Run on the **world database**
   - `NPCdisplayid.sql` → Run on the **world database** (adds display ID 27822)

   > NPC entry ID 90001 is used by default. If you wish to change it, update the ID in `Stockbroker.lua`.

3. Restart the server. The Stock Broker NPC will now handle investments, and stock events will begin firing automatically.

Event Control
-------------

- `.stockevent`  
  Manually triggers a random event (does NOT reset the timer).  
  **Note:** You must be in GM mode to use this command.

Technical Notes
---------------

- All currency is stored securely in the `character_stockmarket` table (`acore_characters`) or your core equivalent.
- Logs include value deltas, percentages, and event descriptions.
- Multiple characters per account can maintain separate investments.

Caution
-------

This script is provided **AS IS**. Support will only be given for unmodified versions. If you alter the code and encounter issues, you're on your own.

Credits
-------

Developed by:  
Doodihealz / Corey

Have fun making (or losing) gold!


INSERT INTO `creature_template` (
    `entry`, `difficulty_entry_1`, `difficulty_entry_2`, `difficulty_entry_3`,
    `KillCredit1`, `KillCredit2`, `modelid1`, `modelid2`, `modelid3`, `modelid4`,
    `name`, `subname`, `IconName`, `gossip_menu_id`, `minlevel`, `maxlevel`, `exp`,
    `faction`, `npcflag`, `speed_walk`, `speed_run`, `speed_swim`, `speed_flight`,
    `detection_range`, `scale`, `rank`, `dmgschool`, `DamageModifier`,
    `BaseAttackTime`, `RangeAttackTime`, `BaseVariance`, `RangeVariance`,
    `unit_class`, `unit_flags`, `unit_flags2`, `dynamicflags`, `family`,
    `trainer_type`, `trainer_spell`, `trainer_class`, `trainer_race`,
    `type`, `type_flags`, `lootid`, `pickpocketloot`, `skinloot`,
    `resistance1`, `resistance2`, `resistance3`, `resistance4`, `resistance5`, `resistance6`,
    `spell1`, `spell2`, `spell3`, `spell4`, `spell5`, `spell6`, `spell7`, `spell8`,
    `PetSpellDataId`, `VehicleId`, `mingold`, `maxgold`, `AIName`, `MovementType`,
    `InhabitType`, `HoverHeight`, `HealthModifier`, `ManaModifier`, `ArmorModifier`,
    `ExperienceModifier`, `RacialLeader`, `movementId`, `RegenHealth`,
    `mechanic_immune_mask`, `spell_school_immune_mask`, `flags_extra`, `ScriptName`, `VerifiedBuild`
) VALUES (
    90001, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    'Stock Broker', 'Invest in the market', '', 0, 70, 70, 0,
    35, 1, 1, 1.14286, 1, 1, 20, 1, 0, 0, 1,
    2000, 2000, 1, 1, 1, 0, 0, 0, 0, 0,
    0, 0, 0, 7, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, '', 0, 0, 1,
    1, 1, 1, 1, 0, 0, 1,
    0, 0, 0, 'npc_stockbroker', NULL
);

INSERT INTO `creature_template_model` (
    `CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`
) VALUES (
    90001, 1, 27822, 1, 1, 0
);

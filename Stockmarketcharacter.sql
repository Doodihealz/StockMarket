-- --------------------------------------------------------
-- Host:                         127.0.0.1
-- Server version:               8.4.4 - MySQL Community Server - GPL
-- Server OS:                    Win64
-- HeidiSQL Version:             12.10.0.7036
-- --------------------------------------------------------

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET NAMES utf8 */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;


-- Dumping database structure for acore_characters
CREATE DATABASE IF NOT EXISTS `acore_characters` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;
USE `acore_characters`;

-- Dumping structure for table acore_characters.character_stockmarket
CREATE TABLE IF NOT EXISTS `character_stockmarket` (
  `guid` int unsigned NOT NULL,
  `InvestedMoney` bigint unsigned NOT NULL DEFAULT '0',
  `last_updated` datetime DEFAULT NULL,
  PRIMARY KEY (`guid`),
  CONSTRAINT `character_stockmarket_ibfk_1` FOREIGN KEY (`guid`) REFERENCES `characters` (`guid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table acore_characters.character_stockmarket: ~0 rows (approximately)

-- Dumping structure for table acore_characters.character_stockmarket_log
CREATE TABLE IF NOT EXISTS `character_stockmarket_log` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `guid` int unsigned NOT NULL,
  `event_id` int unsigned DEFAULT NULL,
  `change_amount` bigint NOT NULL,
  `percent_change` decimal(6,5) DEFAULT NULL,
  `resulting_gold` bigint NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `guid` (`guid`),
  CONSTRAINT `character_stockmarket_log_ibfk_1` FOREIGN KEY (`guid`) REFERENCES `characters` (`guid`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=440 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table acore_characters.character_stockmarket_log: ~0 rows (approximately)
INSERT INTO `character_stockmarket_log` (`id`, `guid`, `event_id`, `change_amount`, `percent_change`, `resulting_gold`, `description`, `created_at`) VALUES
	(439, 2113, 65, 275, 2.75000, 1, 'Market Event: Blacksmithing boom due to rare ore find.', '2025-05-25 20:54:48');

/*!40103 SET TIME_ZONE=IFNULL(@OLD_TIME_ZONE, 'system') */;
/*!40101 SET SQL_MODE=IFNULL(@OLD_SQL_MODE, '') */;
/*!40014 SET FOREIGN_KEY_CHECKS=IFNULL(@OLD_FOREIGN_KEY_CHECKS, 1) */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40111 SET SQL_NOTES=IFNULL(@OLD_SQL_NOTES, 1) */;

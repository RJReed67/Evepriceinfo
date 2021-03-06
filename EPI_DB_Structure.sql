-- MySQL dump 10.13  Distrib 5.5.32, for Linux (x86_64)
--
-- Host: localhost    Database: EvePriceInfo
-- ------------------------------------------------------
-- Server version	5.5.32-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `AuthorizedUsers`
--

DROP TABLE IF EXISTS `AuthorizedUsers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `AuthorizedUsers` (
  `UserKey` int(11) NOT NULL AUTO_INCREMENT,
  `TwitchID` varchar(40) NOT NULL,
  `Owner` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`UserKey`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `BJGame`
--

DROP TABLE IF EXISTS `BJGame`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `BJGame` (
  `BJKey` int(10) unsigned NOT NULL,
  `TwitchID` varchar(40) NOT NULL,
  `Shoe` varchar(624) NOT NULL,
  `Hand` varchar(20) NOT NULL,
  `Dealer` varchar(20) NOT NULL,
  `Bet` int(11) NOT NULL,
  `TTL` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`TwitchID`),
  UNIQUE KEY `TwitchID` (`TwitchID`),
  UNIQUE KEY `TwitchID_2` (`TwitchID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `GameQueue`
--

DROP TABLE IF EXISTS `GameQueue`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `GameQueue` (
  `TwitchID` varchar(40) NOT NULL,
  `QueTime` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00' ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `TwitchID` (`TwitchID`),
  KEY `QueTime` (`QueTime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Match`
--

DROP TABLE IF EXISTS `Match`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Match` (
  `MatchID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `MatchTime` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `NumOfSides` tinyint(11) NOT NULL,
  `A` varchar(100) NOT NULL,
  `B` varchar(100) NOT NULL,
  `C` varchar(100) DEFAULT NULL,
  `D` varchar(100) DEFAULT NULL,
  `E` varchar(100) DEFAULT NULL,
  `F` varchar(100) DEFAULT NULL,
  `MatchWinner` varchar(200) DEFAULT NULL,
  `TotalPool` int(11) DEFAULT NULL,
  `Rake` int(11) DEFAULT NULL,
  PRIMARY KEY (`MatchID`)
) ENGINE=MyISAM AUTO_INCREMENT=163 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `MatchWagers`
--

DROP TABLE IF EXISTS `MatchWagers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `MatchWagers` (
  `WagerID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `MatchID` bigint(20) unsigned NOT NULL,
  `TwitchID` varchar(40) NOT NULL,
  `WagerOnWho` varchar(200) NOT NULL,
  `WagerAmt` int(11) NOT NULL,
  `Odds` float DEFAULT NULL,
  PRIMARY KEY (`WagerID`)
) ENGINE=MyISAM AUTO_INCREMENT=1710 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `PatreonLevels`
--

DROP TABLE IF EXISTS `PatreonLevels`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `PatreonLevels` (
  `PatKey` int(11) NOT NULL,
  `PatName` varchar(40) NOT NULL,
  `PatDesc` varchar(255) NOT NULL,
  PRIMARY KEY (`PatKey`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ProcStatus`
--

DROP TABLE IF EXISTS `ProcStatus`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ProcStatus` (
  `ProcKey` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `ProcName` varchar(15) NOT NULL,
  `ProcFile` varchar(20) NOT NULL,
  `Active` int(11) NOT NULL DEFAULT '1',
  PRIMARY KEY (`ProcKey`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Rushlock_TwitchSubs`
--

DROP TABLE IF EXISTS `Rushlock_TwitchSubs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Rushlock_TwitchSubs` (
  `SubKey` int(11) NOT NULL AUTO_INCREMENT,
  `TwitchName` varchar(50) NOT NULL,
  `SubEmail` varchar(50) NOT NULL,
  `SubLevel` int(11) NOT NULL DEFAULT '5',
  `SubDate` date NOT NULL,
  PRIMARY KEY (`SubKey`)
) ENGINE=MyISAM AUTO_INCREMENT=614 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8 */ ;
/*!50003 SET character_set_results = utf8 */ ;
/*!50003 SET collation_connection  = utf8_general_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = '' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50017 DEFINER=`root`@`localhost`*/ /*!50003 TRIGGER `NewSubGrant` AFTER INSERT ON `Rushlock_TwitchSubs` FOR EACH ROW BEGIN
   SET @TwitchID = NEW.TwitchName;
   SELECT Tokens INTO @Tokens FROM followers WHERE TwitchID LIKE @TwitchID;
   SELECT SubLevel INTO @SubLvl FROM Rushlock_TwitchSubs WHERE TwitchName LIKE @TwitchID ORDER BY SubKey DESC LIMIT 1;
   CASE @SubLvl
      WHEN 1 THEN SET @Tokens = @Tokens + 40;
      WHEN 3 THEN SET @Tokens = @Tokens + 120;
      WHEN 5 THEN SET @Tokens = @Tokens + 200;
      WHEN 10 THEN SET @Tokens = @Tokens + 400;
      WHEN 25 THEN SET @Tokens = @Tokens + 1000;
      WHEN 50 THEN SET @Tokens = @Tokens + 2000;
      WHEN 100 THEN SET @Tokens = @Tokens + 4000;
   END CASE;
   UPDATE followers SET Tokens = @Tokens WHERE TwitchID LIKE @TwitchID;
END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;

--
-- Table structure for table `Rushlock_WeeklyTokenCount`
--

DROP TABLE IF EXISTS `Rushlock_WeeklyTokenCount`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Rushlock_WeeklyTokenCount` (
  `TwitchID` varchar(50) NOT NULL,
  `Token` int(11) NOT NULL,
  PRIMARY KEY (`TwitchID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `SlotTime`
--

DROP TABLE IF EXISTS `SlotTime`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `SlotTime` (
  `TwitchID` varchar(40) NOT NULL,
  `SlotTime` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00' ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `TwitchID` (`TwitchID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `TipJar`
--

DROP TABLE IF EXISTS `TipJar`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `TipJar` (
  `TotalTokens` int(11) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `TipTime`
--

DROP TABLE IF EXISTS `TipTime`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `TipTime` (
  `TipperID` varchar(40) NOT NULL,
  `TipTime` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00' ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`TipperID`),
  UNIQUE KEY `TipperID` (`TipperID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `TokenStats`
--

DROP TABLE IF EXISTS `TokenStats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `TokenStats` (
  `StatKey` int(11) NOT NULL AUTO_INCREMENT,
  `StatDate` date NOT NULL,
  `TotalTokens` bigint(20) unsigned NOT NULL,
  `RakedTokens` int(11) unsigned NOT NULL DEFAULT '0',
  `MatchTokens` int(11) unsigned NOT NULL DEFAULT '0',
  `TippedTokensIn` int(11) unsigned NOT NULL DEFAULT '0',
  `TippedTokensOut` int(10) unsigned NOT NULL DEFAULT '0',
  `BJTokensIn` int(11) unsigned NOT NULL DEFAULT '0',
  `BJTokensOut` int(10) unsigned NOT NULL DEFAULT '0',
  `SlotTokensIn` int(11) unsigned NOT NULL DEFAULT '0',
  `SlotTokensOut` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`StatKey`)
) ENGINE=MyISAM AUTO_INCREMENT=17 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `TwitterID2TwitchID`
--

DROP TABLE IF EXISTS `TwitterID2TwitchID`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `TwitterID2TwitchID` (
  `TwitchID` varchar(50) NOT NULL,
  `TwitterID` varchar(50) NOT NULL,
  `TTL` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `TwitterInfo`
--

DROP TABLE IF EXISTS `TwitterInfo`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `TwitterInfo` (
  `Count` int(11) NOT NULL AUTO_INCREMENT,
  `Tweet` varchar(200) NOT NULL,
  PRIMARY KEY (`Count`)
) ENGINE=InnoDB AUTO_INCREMENT=12 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `channel_status`
--

DROP TABLE IF EXISTS `channel_status`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `channel_status` (
  `ChannelKey` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Channel` varchar(50) NOT NULL,
  `Status` enum('Online','Offline','Unknown') NOT NULL DEFAULT 'Offline',
  PRIMARY KEY (`ChannelKey`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `entrylist`
--

DROP TABLE IF EXISTS `entrylist`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `entrylist` (
  `TwitchID` varchar(50) NOT NULL,
  UNIQUE KEY `TwitchID` (`TwitchID`)
) ENGINE=MEMORY DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `epi_commands`
--

DROP TABLE IF EXISTS `epi_commands`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `epi_commands` (
  `CmdKey` int(11) NOT NULL AUTO_INCREMENT,
  `Command` varchar(30) NOT NULL,
  `HelpInfo` varchar(255) NOT NULL,
  `CmdType` enum('info','custom','internal') NOT NULL,
  `CmdModule` varchar(25) NOT NULL,
  `Repeat` tinyint(1) NOT NULL DEFAULT '0',
  `CycleTime` int(11) NOT NULL DEFAULT '0',
  `NumOfChatLines` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`CmdKey`)
) ENGINE=MyISAM AUTO_INCREMENT=134 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `epi_configuration`
--

DROP TABLE IF EXISTS `epi_configuration`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `epi_configuration` (
  `setting` varchar(50) NOT NULL,
  `value` varchar(125) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `epi_info_cmds`
--

DROP TABLE IF EXISTS `epi_info_cmds`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `epi_info_cmds` (
  `CmdName` varchar(30) NOT NULL,
  `DisplayInfo` mediumtext NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `followers`
--

DROP TABLE IF EXISTS `followers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `followers` (
  `UserKey` bigint(20) NOT NULL AUTO_INCREMENT,
  `TwitchID` varchar(40) NOT NULL,
  `Tokens` int(11) NOT NULL,
  `TTL` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`UserKey`),
  KEY `TwitchID` (`TwitchID`)
) ENGINE=InnoDB AUTO_INCREMENT=65959 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `giveaway`
--

DROP TABLE IF EXISTS `giveaway`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `giveaway` (
  `GiveKey` bigint(20) NOT NULL AUTO_INCREMENT,
  `GiveTitle` varchar(255) NOT NULL,
  `Threshold` int(11) NOT NULL,
  `AutoGive` tinyint(1) NOT NULL DEFAULT '0',
  `StartDate` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  `EndDate` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  `Winner` varchar(50) NOT NULL,
  PRIMARY KEY (`GiveKey`)
) ENGINE=InnoDB AUTO_INCREMENT=6767 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `icerefine`
--

DROP TABLE IF EXISTS `icerefine`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `icerefine` (
  `IceType` varchar(30) NOT NULL,
  `RefineSize` int(11) NOT NULL,
  `Heavy Water` int(11) NOT NULL,
  `Helium Isotopes` int(11) NOT NULL,
  `Hydrogen Isotopes` int(11) NOT NULL,
  `Nitrogen Isotopes` int(11) NOT NULL,
  `Oxygen Isotopes` int(11) NOT NULL,
  `Liquid Ozone` int(11) NOT NULL,
  `Strontium Calthrates` int(11) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `invTypes`
--

DROP TABLE IF EXISTS `invTypes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `invTypes` (
  `typeID` int(11) NOT NULL,
  `groupID` int(11) DEFAULT NULL,
  `typeName` varchar(100) DEFAULT NULL,
  `description` varchar(3000) DEFAULT NULL,
  `mass` double DEFAULT NULL,
  `volume` double DEFAULT NULL,
  `capacity` double DEFAULT NULL,
  `portionSize` int(11) DEFAULT NULL,
  `raceID` tinyint(3) unsigned DEFAULT NULL,
  `basePrice` decimal(19,4) DEFAULT NULL,
  `published` tinyint(1) DEFAULT NULL,
  `marketGroupID` int(11) DEFAULT NULL,
  `chanceOfDuplicating` double DEFAULT NULL,
  PRIMARY KEY (`typeID`),
  KEY `invTypes_IX_Group` (`groupID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `killcache`
--

DROP TABLE IF EXISTS `killcache`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `killcache` (
  `CharID` int(11) NOT NULL,
  `CharName` varchar(50) NOT NULL,
  `DestShips` int(11) NOT NULL,
  `DestISK` double(15,2) NOT NULL,
  `LostShips` int(11) NOT NULL,
  `LostISK` double(15,2) NOT NULL,
  `DataExpire` datetime NOT NULL,
  PRIMARY KEY (`CharID`),
  UNIQUE KEY `CharID` (`CharID`)
) ENGINE=MEMORY DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `refineInfo`
--

DROP TABLE IF EXISTS `refineInfo`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `refineInfo` (
  `refineItem` varchar(50) NOT NULL,
  `batchsize` int(11) NOT NULL,
  `Tritanium` int(11) NOT NULL,
  `Pyerite` int(11) NOT NULL,
  `Mexallon` int(11) NOT NULL,
  `Isogen` int(11) NOT NULL,
  `Nocxium` int(11) NOT NULL,
  `Zydrine` int(11) NOT NULL,
  `Megacyte` int(11) NOT NULL,
  `Morphite` int(11) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `regionids`
--

DROP TABLE IF EXISTS `regionids`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `regionids` (
  `RegionID` int(11) NOT NULL,
  `RegionName` varchar(50) NOT NULL,
  PRIMARY KEY (`RegionID`),
  KEY `RegionID` (`RegionID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `rushlock_online_viewers`
--

DROP TABLE IF EXISTS `rushlock_online_viewers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `rushlock_online_viewers` (
  `TwitchID` varchar(50) NOT NULL,
  UNIQUE KEY `TwitchID` (`TwitchID`),
  KEY `TwitchID_2` (`TwitchID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `systemids`
--

DROP TABLE IF EXISTS `systemids`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `systemids` (
  `SystemID` int(11) NOT NULL,
  `SystemName` varchar(50) NOT NULL,
  `RegionID` int(11) NOT NULL,
  `Faction` int(11) NOT NULL,
  `Securty` decimal(20,19) NOT NULL,
  `ConstellationID` int(11) NOT NULL,
  `TrueSec` decimal(20,19) NOT NULL,
  PRIMARY KEY (`SystemID`),
  KEY `SystemID` (`SystemID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `token_log`
--

DROP TABLE IF EXISTS `token_log`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `token_log` (
  `log_id` int(11) NOT NULL AUTO_INCREMENT,
  `log_source` varchar(100) NOT NULL DEFAULT '',
  `log_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `log_level` varchar(10) NOT NULL DEFAULT '',
  `log_mesg` varchar(200) NOT NULL DEFAULT '',
  PRIMARY KEY (`log_id`),
  KEY `log_date_idx` (`log_date`),
  KEY `log_source_idx` (`log_source`),
  KEY `log_mesg_idx` (`log_mesg`)
) ENGINE=MyISAM AUTO_INCREMENT=1276681 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2015-07-18  0:05:01

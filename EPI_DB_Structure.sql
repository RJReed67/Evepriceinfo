-- phpMyAdmin SQL Dump
-- version 3.5.8.1
-- http://www.phpmyadmin.net
--

SET SQL_MODE="NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;

--
-- Database: `EvePriceInfo`
--
CREATE DATABASE `EvePriceInfo` DEFAULT CHARACTER SET latin1 COLLATE latin1_swedish_ci;
USE `EvePriceInfo`;

-- --------------------------------------------------------

--
-- Table structure for table `Rushlock_TwitchSubs`
--

DROP TABLE IF EXISTS `Rushlock_TwitchSubs`;
CREATE TABLE IF NOT EXISTS `Rushlock_TwitchSubs` (
  `SubKey` int(11) NOT NULL AUTO_INCREMENT,
  `TwitchName` varchar(50) NOT NULL,
  `SubEmail` varchar(50) NOT NULL,
  `SubDate` date NOT NULL,
  PRIMARY KEY (`SubKey`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1 AUTO_INCREMENT=49 ;

--
-- Triggers `Rushlock_TwitchSubs`
--
DROP TRIGGER IF EXISTS `NewSubGrant`;
DELIMITER //
CREATE TRIGGER `NewSubGrant` AFTER INSERT ON `Rushlock_TwitchSubs`
 FOR EACH ROW BEGIN

   SET @TwitchID = NEW.TwitchName;

   SELECT Tokens INTO @Tokens FROM followers WHERE TwitchID LIKE @TwitchID;

   SET @Tokens = @Tokens + 200;

   UPDATE followers SET Tokens = @Tokens WHERE TwitchID LIKE @TwitchID;

END
//
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `Rushlock_WeeklyTokenCount`
--

DROP TABLE IF EXISTS `Rushlock_WeeklyTokenCount`;
CREATE TABLE IF NOT EXISTS `Rushlock_WeeklyTokenCount` (
  `TwitchID` varchar(50) NOT NULL,
  `Token` int(11) NOT NULL,
  PRIMARY KEY (`TwitchID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `TwitterID2TwitchID`
--

DROP TABLE IF EXISTS `TwitterID2TwitchID`;
CREATE TABLE IF NOT EXISTS `TwitterID2TwitchID` (
  `TwitchID` varchar(50) NOT NULL,
  `TwitterID` varchar(50) NOT NULL,
  `TTL` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `WeeklyGiveaway`
--

DROP TABLE IF EXISTS `WeeklyGiveaway`;
CREATE TABLE IF NOT EXISTS `WeeklyGiveaway` (
  `GiveID` int(11) NOT NULL,
  `TwitchID` varchar(50) NOT NULL,
  PRIMARY KEY (`GiveID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `entrylist`
--

DROP TABLE IF EXISTS `entrylist`;
CREATE TABLE IF NOT EXISTS `entrylist` (
  `TwitchID` varchar(50) NOT NULL,
  UNIQUE KEY `TwitchID` (`TwitchID`)
) ENGINE=MEMORY DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `epi_commands`
--

DROP TABLE IF EXISTS `epi_commands`;
CREATE TABLE IF NOT EXISTS `epi_commands` (
  `CmdKey` int(11) NOT NULL AUTO_INCREMENT,
  `Command` varchar(30) NOT NULL,
  `HelpInfo` varchar(255) NOT NULL,
  `CmdType` enum('info','custom','internal') NOT NULL,
  PRIMARY KEY (`CmdKey`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1 AUTO_INCREMENT=89 ;

-- --------------------------------------------------------

--
-- Table structure for table `epi_configuration`
--

DROP TABLE IF EXISTS `epi_configuration`;
CREATE TABLE IF NOT EXISTS `epi_configuration` (
  `setting` varchar(50) NOT NULL,
  `value` varchar(125) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `epi_info_cmds`
--

DROP TABLE IF EXISTS `epi_info_cmds`;
CREATE TABLE IF NOT EXISTS `epi_info_cmds` (
  `CmdName` varchar(30) NOT NULL,
  `DisplayInfo` varchar(255) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `followers`
--

DROP TABLE IF EXISTS `followers`;
CREATE TABLE IF NOT EXISTS `followers` (
  `UserKey` bigint(20) NOT NULL AUTO_INCREMENT,
  `TwitchID` varchar(40) NOT NULL,
  `Tokens` int(11) NOT NULL,
  `TTL` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`UserKey`),
  KEY `TwitchID` (`TwitchID`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1 AUTO_INCREMENT=13536 ;

-- --------------------------------------------------------

--
-- Table structure for table `giveaway`
--

DROP TABLE IF EXISTS `giveaway`;
CREATE TABLE IF NOT EXISTS `giveaway` (
  `GiveKey` bigint(20) NOT NULL AUTO_INCREMENT,
  `GiveTitle` varchar(255) NOT NULL,
  `Threshold` int(11) NOT NULL,
  `AutoGive` tinyint(1) NOT NULL DEFAULT '0',
  `StartDate` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  `EndDate` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  `Winner` varchar(50) NOT NULL,
  PRIMARY KEY (`GiveKey`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1 AUTO_INCREMENT=67 ;

-- --------------------------------------------------------

--
-- Table structure for table `icerefine`
--

DROP TABLE IF EXISTS `icerefine`;
CREATE TABLE IF NOT EXISTS `icerefine` (
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

-- --------------------------------------------------------

--
-- Table structure for table `invTypes`
--

DROP TABLE IF EXISTS `invTypes`;
CREATE TABLE IF NOT EXISTS `invTypes` (
  `typeID` int(11) NOT NULL,
  `groupID` int(11) DEFAULT NULL,
  `typeName` varchar(100) DEFAULT NULL,
  `description` varchar(3000) DEFAULT NULL,
  `mass` double DEFAULT NULL,
  `volume` double DEFAULT NULL,
  `capacity` double DEFAULT NULL,
  `portionSize` int(11) DEFAULT NULL,
  `raceID` int(11) DEFAULT NULL,
  `basePrice` decimal(19,4) DEFAULT NULL,
  `published` int(11) DEFAULT NULL,
  `marketGroupID` int(11) DEFAULT NULL,
  `chanceOfDuplicating` double DEFAULT NULL,
  PRIMARY KEY (`typeID`),
  KEY `invTypes_IX_Group` (`groupID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- --------------------------------------------------------

--
-- Table structure for table `killcache`
--

DROP TABLE IF EXISTS `killcache`;
CREATE TABLE IF NOT EXISTS `killcache` (
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

-- --------------------------------------------------------

--
-- Table structure for table `refineInfo`
--

DROP TABLE IF EXISTS `refineInfo`;
CREATE TABLE IF NOT EXISTS `refineInfo` (
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

-- --------------------------------------------------------

--
-- Table structure for table `regionids`
--

DROP TABLE IF EXISTS `regionids`;
CREATE TABLE IF NOT EXISTS `regionids` (
  `RegionID` int(11) NOT NULL,
  `RegionName` varchar(50) NOT NULL,
  PRIMARY KEY (`RegionID`),
  KEY `RegionID` (`RegionID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `rushlock_online_viewers`
--

DROP TABLE IF EXISTS `rushlock_online_viewers`;
CREATE TABLE IF NOT EXISTS `rushlock_online_viewers` (
  `TwitchID` varchar(50) NOT NULL,
  UNIQUE KEY `TwitchID` (`TwitchID`),
  KEY `TwitchID_2` (`TwitchID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `systemids`
--

DROP TABLE IF EXISTS `systemids`;
CREATE TABLE IF NOT EXISTS `systemids` (
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

-- --------------------------------------------------------

DELIMITER $$
--
-- Events
--
DROP EVENT `WeeklyTokenCleanUp`$$
CREATE DEFINER=`root`@`localhost` EVENT `WeeklyTokenCleanUp` ON SCHEDULE EVERY 1 WEEK STARTS '2013-11-30 00:00:00' ON COMPLETION PRESERVE ENABLE COMMENT 'Cleans the table out each week' DO TRUNCATE Rushlock_WeeklyTokenCount$$

DROP EVENT `DeleteOldUsers`$$
CREATE DEFINER=`root`@`localhost` EVENT `DeleteOldUsers` ON SCHEDULE EVERY 1 DAY STARTS '2014-01-08 00:00:01' ON COMPLETION NOT PRESERVE ENABLE COMMENT 'Daily delete of followers table that are over 90 days offline' DO DELETE FROM `followers` WHERE DATEDIFF( NOW(), `TTL`) > 90$$

DELIMITER ;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */

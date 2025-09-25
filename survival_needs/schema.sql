-- survival_needs schema for ox_mysql
CREATE TABLE IF NOT EXISTS `survival_needs` (
  `license`    VARCHAR(80) NOT NULL,
  `data`       JSON NOT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Optional index if you will query by recency
CREATE INDEX IF NOT EXISTS `survival_needs_updated_at_idx`
  ON `survival_needs` (`updated_at`);

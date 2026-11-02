# ASR evaluation: balanced

| | |
| --- | --- |
| Corpus | `fleurs-fil_ph-test-onepersentence-seed7` |
| Items scored | 349 of 349 |
| Configuration | `notero-eval-v1` (schema 1), fingerprint `96fdf032732a3b31` |
| Scoring policy | `notero-standard` v1, fingerprint `5c0946fada2f868b` |
| System | balanced |
| Model | `openai_whisper-large-v3-v20240930_turbo` |
| Model revision | `0f63a7800b00dd0226abd051b906c246e1907482` |
| Build | `5f34fbcffa1a756b2dcdc9cf1fc20ecb53970c78` |
| Hardware | Mac14,12 · 10 cores · macOS 26.6, 16 GB |
| Inference | mode offline, language tl, diarization off, roomMode false, styleHint false |

Policy: Unicode NFKC, case folded, diacritics kept, punctuation removed, hyphens split words, intra-word apostrophes kept, contractions as written.

## Accuracy

| Metric | Value | 95% interval | N | Sub | Del | Ins |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| WER | 11.66% | 10.73% to 12.64% | 9613 | 869 | 123 | 129 |
| CER | 3.64% | 3.14% to 4.19% | 57364 | 678 | 799 | 609 |

Interval: percentile bootstrap of the pooled rate ΣE/ΣN, type-7 quantiles, SplitMix64; 2000 resamples of 349 utterances, seed 20261102, stratified by utterance language class.

### By utterance language

| Stratum | Utterances | WER | CER | N | Sub | Del | Ins |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| tagalog | 349 | 11.66% | 3.64% | 9613 | 869 | 123 | 129 |

### By word language

Covers 349 of 349 scored items: fleurs-1660, fleurs-1661, fleurs-1662, fleurs-1663, fleurs-1664, fleurs-1665, fleurs-1666, fleurs-1667, fleurs-1668, fleurs-1669, fleurs-1670, fleurs-1671, fleurs-1672, fleurs-1673, fleurs-1674, fleurs-1675, fleurs-1676, fleurs-1677, fleurs-1678, fleurs-1679, fleurs-1680, fleurs-1681, fleurs-1682, fleurs-1683, fleurs-1684, fleurs-1685, fleurs-1686, fleurs-1687, fleurs-1688, fleurs-1689, fleurs-1690, fleurs-1691, fleurs-1692, fleurs-1693, fleurs-1694, fleurs-1695, fleurs-1696, fleurs-1697, fleurs-1698, fleurs-1699, fleurs-1700, fleurs-1701, fleurs-1702, fleurs-1703, fleurs-1704, fleurs-1705, fleurs-1706, fleurs-1707, fleurs-1708, fleurs-1709, fleurs-1710, fleurs-1711, fleurs-1712, fleurs-1713, fleurs-1714, fleurs-1715, fleurs-1716, fleurs-1717, fleurs-1718, fleurs-1719, fleurs-1720, fleurs-1721, fleurs-1722, fleurs-1723, fleurs-1724, fleurs-1725, fleurs-1726, fleurs-1727, fleurs-1728, fleurs-1729, fleurs-1730, fleurs-1731, fleurs-1732, fleurs-1733, fleurs-1734, fleurs-1735, fleurs-1736, fleurs-1737, fleurs-1738, fleurs-1739, fleurs-1740, fleurs-1741, fleurs-1742, fleurs-1743, fleurs-1744, fleurs-1745, fleurs-1746, fleurs-1747, fleurs-1748, fleurs-1749, fleurs-1750, fleurs-1751, fleurs-1752, fleurs-1753, fleurs-1754, fleurs-1755, fleurs-1756, fleurs-1757, fleurs-1758, fleurs-1759, fleurs-1760, fleurs-1761, fleurs-1762, fleurs-1763, fleurs-1764, fleurs-1765, fleurs-1766, fleurs-1767, fleurs-1768, fleurs-1769, fleurs-1770, fleurs-1771, fleurs-1772, fleurs-1773, fleurs-1774, fleurs-1775, fleurs-1776, fleurs-1777, fleurs-1778, fleurs-1779, fleurs-1780, fleurs-1781, fleurs-1782, fleurs-1783, fleurs-1784, fleurs-1785, fleurs-1786, fleurs-1787, fleurs-1788, fleurs-1789, fleurs-1790, fleurs-1791, fleurs-1792, fleurs-1793, fleurs-1794, fleurs-1795, fleurs-1796, fleurs-1797, fleurs-1798, fleurs-1799, fleurs-1800, fleurs-1801, fleurs-1802, fleurs-1803, fleurs-1804, fleurs-1805, fleurs-1806, fleurs-1807, fleurs-1808, fleurs-1809, fleurs-1810, fleurs-1811, fleurs-1812, fleurs-1813, fleurs-1814, fleurs-1815, fleurs-1816, fleurs-1817, fleurs-1818, fleurs-1819, fleurs-1820, fleurs-1821, fleurs-1822, fleurs-1824, fleurs-1825, fleurs-1826, fleurs-1827, fleurs-1828, fleurs-1829, fleurs-1830, fleurs-1831, fleurs-1832, fleurs-1833, fleurs-1834, fleurs-1835, fleurs-1836, fleurs-1837, fleurs-1838, fleurs-1839, fleurs-1840, fleurs-1841, fleurs-1842, fleurs-1843, fleurs-1844, fleurs-1845, fleurs-1846, fleurs-1847, fleurs-1848, fleurs-1849, fleurs-1850, fleurs-1851, fleurs-1852, fleurs-1853, fleurs-1854, fleurs-1855, fleurs-1856, fleurs-1857, fleurs-1858, fleurs-1859, fleurs-1860, fleurs-1861, fleurs-1862, fleurs-1863, fleurs-1864, fleurs-1865, fleurs-1866, fleurs-1867, fleurs-1868, fleurs-1869, fleurs-1870, fleurs-1871, fleurs-1872, fleurs-1873, fleurs-1874, fleurs-1875, fleurs-1876, fleurs-1877, fleurs-1878, fleurs-1879, fleurs-1880, fleurs-1881, fleurs-1882, fleurs-1883, fleurs-1884, fleurs-1885, fleurs-1886, fleurs-1887, fleurs-1888, fleurs-1889, fleurs-1890, fleurs-1891, fleurs-1892, fleurs-1893, fleurs-1894, fleurs-1895, fleurs-1896, fleurs-1897, fleurs-1898, fleurs-1899, fleurs-1900, fleurs-1901, fleurs-1902, fleurs-1903, fleurs-1904, fleurs-1905, fleurs-1906, fleurs-1907, fleurs-1908, fleurs-1909, fleurs-1910, fleurs-1911, fleurs-1912, fleurs-1913, fleurs-1914, fleurs-1915, fleurs-1916, fleurs-1917, fleurs-1918, fleurs-1919, fleurs-1920, fleurs-1921, fleurs-1922, fleurs-1923, fleurs-1924, fleurs-1925, fleurs-1926, fleurs-1927, fleurs-1928, fleurs-1929, fleurs-1930, fleurs-1931, fleurs-1932, fleurs-1933, fleurs-1934, fleurs-1935, fleurs-1936, fleurs-1937, fleurs-1938, fleurs-1939, fleurs-1940, fleurs-1941, fleurs-1942, fleurs-1943, fleurs-1944, fleurs-1945, fleurs-1946, fleurs-1947, fleurs-1948, fleurs-1949, fleurs-1950, fleurs-1951, fleurs-1952, fleurs-1953, fleurs-1954, fleurs-1955, fleurs-1956, fleurs-1957, fleurs-1958, fleurs-1959, fleurs-1960, fleurs-1961, fleurs-1962, fleurs-1963, fleurs-1964, fleurs-1965, fleurs-1966, fleurs-1967, fleurs-1968, fleurs-1969, fleurs-1970, fleurs-1971, fleurs-1972, fleurs-1973, fleurs-1974, fleurs-1975, fleurs-1976, fleurs-1977, fleurs-1978, fleurs-1979, fleurs-1980, fleurs-1981, fleurs-1982, fleurs-1983, fleurs-1984, fleurs-1985, fleurs-1986, fleurs-1987, fleurs-1988, fleurs-1989, fleurs-1990, fleurs-1991, fleurs-1992, fleurs-1993, fleurs-1994, fleurs-1995, fleurs-1996, fleurs-1997, fleurs-1998, fleurs-1999, fleurs-2000, fleurs-2001, fleurs-2002, fleurs-2003, fleurs-2004, fleurs-2005, fleurs-2006, fleurs-2007, fleurs-2008, fleurs-2009.

Rates are (substitutions + deletions) / reference words of that language. Insertions have no reference word and are left out of them.

| Words | Reference words | Hits | Sub | Del | (S+D)/N |
| --- | ---: | ---: | ---: | ---: | ---: |
| tl | 9613 | 8621 | 869 | 123 | 10.32% |
| at a code switch | unavailable: no item has word-level language spans for code-switch points | | | | |
| not at a switch | unavailable: no item has word-level language spans for non-switch points | | | | |

Insertions not attributed to a language: 129. Reference words with no word-level language: 0.

### By speaker overlap

Unavailable: the reference has no overlap annotation and no timed speaker turns.

## Deletions and missing speech

Deletion bursts (at least 3 consecutive reference words deleted): 5, 30 words, 123 deletions in all.

| Item | First utterance | Words | Time | Deleted |
| --- | --- | ---: | --- | --- |
| fleurs-1682 | line-1 | 11 | untimed | may sukat ito na 29â3 4 pulgada por 24â1 2 pulgada |
| fleurs-1730 | line-1 | 4 | untimed | sa kabila ng ilog |
| fleurs-1732 | line-1 | 3 | untimed | ad 1000 1300 |
| fleurs-1855 | line-1 | 5 | untimed | subalit hindi ibang malalaking pusa |
| fleurs-1888 | line-1 | 7 | untimed | mayroon itong mas kaunting yugto ng pulutgata |

Missing speech: unavailable: the reference has no timestamps.

## Performance

Four different figures. A smaller process footprint is not a smaller model: the model's Neural Engine memory is not in the footprint.

| Item | Whole-file RTF (offline) | Live commit latency | Process peak footprint | Model residency |
| --- | --- | --- | --- | --- |
| **Corpus** | 0.068 | | | |
| fleurs-1660 | 0.065 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1661 | 0.067 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1662 | 0.065 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1663 | 0.085 | unavailable: an offline run has no commit latency | 234 MB | 1580 MB |
| fleurs-1664 | 0.062 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1665 | 0.049 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1666 | 0.062 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1667 | 0.067 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1668 | 0.069 | unavailable: an offline run has no commit latency | 135 MB | 1580 MB |
| fleurs-1669 | 0.088 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1670 | 0.074 | unavailable: an offline run has no commit latency | 241 MB | 1580 MB |
| fleurs-1671 | 0.056 | unavailable: an offline run has no commit latency | 139 MB | 1580 MB |
| fleurs-1672 | 0.092 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1673 | 0.085 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1674 | 0.069 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1675 | 0.064 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1676 | 0.067 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1677 | 0.121 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1678 | 0.044 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1679 | 0.139 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1680 | 0.056 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1681 | 0.076 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1682 | 0.086 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1683 | 0.080 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1684 | 0.055 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1685 | 0.057 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1686 | 0.053 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1687 | 0.117 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1688 | 0.060 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1689 | 0.066 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1690 | 0.084 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1691 | 0.103 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1692 | 0.071 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1693 | 0.061 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1694 | 0.061 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1695 | 0.059 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1696 | 0.073 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1697 | 0.109 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1698 | 0.074 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1699 | 0.062 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1700 | 0.113 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1701 | 0.055 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1702 | 0.090 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1703 | 0.064 | unavailable: an offline run has no commit latency | 135 MB | 1580 MB |
| fleurs-1704 | 0.058 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1705 | 0.048 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1706 | 0.080 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1707 | 0.059 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1708 | 0.047 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1709 | 0.052 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1710 | 0.054 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1711 | 0.061 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1712 | 0.052 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1713 | 0.070 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1714 | 0.066 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1715 | 0.059 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1716 | 0.078 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1717 | 0.068 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1718 | 0.089 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1719 | 0.057 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1720 | 0.064 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1721 | 0.053 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1722 | 0.050 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1723 | 0.045 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1724 | 0.062 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1725 | 0.050 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1726 | 0.065 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1727 | 0.063 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1728 | 0.063 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1729 | 0.074 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1730 | 0.076 | unavailable: an offline run has no commit latency | 132 MB | 1580 MB |
| fleurs-1731 | 0.072 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1732 | 0.080 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1733 | 0.061 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1734 | 0.082 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1735 | 0.076 | unavailable: an offline run has no commit latency | 138 MB | 1580 MB |
| fleurs-1736 | 0.075 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1737 | 0.065 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1738 | 0.069 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1739 | 0.107 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1740 | 0.057 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1741 | 0.075 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1742 | 0.079 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1743 | 0.075 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1744 | 0.072 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1745 | 0.102 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1746 | 0.108 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1747 | 0.084 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1748 | 0.126 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1749 | 0.049 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1750 | 0.092 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1751 | 0.052 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1752 | 0.066 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1753 | 0.056 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1754 | 0.082 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1755 | 0.080 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1756 | 0.078 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1757 | 0.089 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1758 | 0.062 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1759 | 0.069 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1760 | 0.064 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1761 | 0.053 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1762 | 0.132 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1763 | 0.059 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1764 | 0.112 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1765 | 0.062 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1766 | 0.064 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1767 | 0.061 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1768 | 0.071 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1769 | 0.057 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1770 | 0.078 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1771 | 0.086 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1772 | 0.080 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1773 | 0.064 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1774 | 0.058 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1775 | 0.058 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1776 | 0.046 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1777 | 0.090 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1778 | 0.090 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1779 | 0.069 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1780 | 0.076 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1781 | 0.070 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1782 | 0.047 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1783 | 0.057 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1784 | 0.059 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1785 | 0.065 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1786 | 0.049 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1787 | 0.061 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1788 | 0.055 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1789 | 0.040 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1790 | 0.089 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1791 | 0.077 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1792 | 0.073 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1793 | 0.103 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1794 | 0.064 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1795 | 0.057 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1796 | 0.080 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1797 | 0.059 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1798 | 0.059 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1799 | 0.074 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1800 | 0.062 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1801 | 0.098 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1802 | 0.069 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1803 | 0.078 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1804 | 0.069 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1805 | 0.069 | unavailable: an offline run has no commit latency | 132 MB | 1580 MB |
| fleurs-1806 | 0.057 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1807 | 0.065 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1808 | 0.053 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1809 | 0.091 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1810 | 0.084 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1811 | 0.054 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1812 | 0.094 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1813 | 0.081 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1814 | 0.058 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1815 | 0.090 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1816 | 0.072 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1817 | 0.079 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1818 | 0.107 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1819 | 0.061 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1820 | 0.114 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1821 | 0.063 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1822 | 0.057 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1824 | 0.053 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1825 | 0.079 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1826 | 0.068 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1827 | 0.046 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1828 | 0.056 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1829 | 0.065 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1830 | 0.045 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1831 | 0.092 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1832 | 0.045 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1833 | 0.078 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1834 | 0.061 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1835 | 0.086 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1836 | 0.170 | unavailable: an offline run has no commit latency | 139 MB | 1580 MB |
| fleurs-1837 | 0.070 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1838 | 0.070 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1839 | 0.078 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1840 | 0.089 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1841 | 0.087 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1842 | 0.076 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1843 | 0.055 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1844 | 0.100 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1845 | 0.057 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1846 | 0.085 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1847 | 0.055 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1848 | 0.081 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1849 | 0.072 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1850 | 0.074 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1851 | 0.071 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1852 | 0.093 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1853 | 0.070 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1854 | 0.066 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1855 | 0.092 | unavailable: an offline run has no commit latency | 135 MB | 1580 MB |
| fleurs-1856 | 0.094 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1857 | 0.066 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1858 | 0.064 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1859 | 0.062 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1860 | 0.076 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1861 | 0.065 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1862 | 0.066 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1863 | 0.071 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1864 | 0.042 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1865 | 0.087 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1866 | 0.102 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1867 | 0.088 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1868 | 0.057 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1869 | 0.056 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1870 | 0.083 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1871 | 0.137 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1872 | 0.074 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1873 | 0.067 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1874 | 0.054 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1875 | 0.066 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1876 | 0.105 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1877 | 0.069 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1878 | 0.050 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1879 | 0.078 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1880 | 0.074 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1881 | 0.058 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1882 | 0.080 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1883 | 0.051 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1884 | 0.058 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1885 | 0.058 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1886 | 0.065 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1887 | 0.073 | unavailable: an offline run has no commit latency | 132 MB | 1580 MB |
| fleurs-1888 | 0.096 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1889 | 0.075 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1890 | 0.065 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1891 | 0.073 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1892 | 0.061 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1893 | 0.054 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1894 | 0.108 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1895 | 0.062 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1896 | 0.066 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1897 | 0.095 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1898 | 0.059 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1899 | 0.070 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1900 | 0.112 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1901 | 0.085 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1902 | 0.064 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1903 | 0.070 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1904 | 0.104 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1905 | 0.107 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1906 | 0.108 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1907 | 0.095 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1908 | 0.128 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1909 | 0.058 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1910 | 0.085 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1911 | 0.100 | unavailable: an offline run has no commit latency | 135 MB | 1580 MB |
| fleurs-1912 | 0.072 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1913 | 0.091 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1914 | 0.055 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1915 | 0.066 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1916 | 0.070 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1917 | 0.118 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1918 | 0.060 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1919 | 0.074 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1920 | 0.082 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1921 | 0.086 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1922 | 0.080 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1923 | 0.077 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1924 | 0.069 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1925 | 0.085 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1926 | 0.130 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1927 | 0.053 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1928 | 0.051 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1929 | 0.067 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1930 | 0.097 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1931 | 0.058 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1932 | 0.070 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1933 | 0.063 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1934 | 0.066 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1935 | 0.080 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1936 | 0.070 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1937 | 0.060 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1938 | 0.063 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1939 | 0.065 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1940 | 0.053 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1941 | 0.078 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1942 | 0.060 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1943 | 0.085 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1944 | 0.097 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1945 | 0.066 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1946 | 0.049 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1947 | 0.066 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1948 | 0.075 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1949 | 0.064 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1950 | 0.074 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1951 | 0.059 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1952 | 0.054 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1953 | 0.069 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1954 | 0.058 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1955 | 0.062 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1956 | 0.056 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1957 | 0.084 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1958 | 0.066 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1959 | 0.068 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1960 | 0.055 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1961 | 0.059 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1962 | 0.081 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1963 | 0.056 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1964 | 0.077 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1965 | 0.066 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1966 | 0.059 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1967 | 0.074 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1968 | 0.085 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1969 | 0.066 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1970 | 0.061 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1971 | 0.062 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1972 | 0.071 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1973 | 0.086 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1974 | 0.127 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1975 | 0.058 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1976 | 0.065 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1977 | 0.057 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1978 | 0.079 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1979 | 0.065 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1980 | 0.067 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1981 | 0.063 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1982 | 0.065 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1983 | 0.062 | unavailable: an offline run has no commit latency | 132 MB | 1580 MB |
| fleurs-1984 | 0.051 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1985 | 0.064 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1986 | 0.047 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1987 | 0.067 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1988 | 0.061 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1989 | 0.055 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1990 | 0.080 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1991 | 0.061 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1992 | 0.079 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1993 | 0.059 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1994 | 0.065 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1995 | 0.084 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1996 | 0.083 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-1997 | 0.058 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1998 | 0.072 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-1999 | 0.053 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-2000 | 0.063 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-2001 | 0.054 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-2002 | 0.059 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-2003 | 0.072 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-2004 | 0.089 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-2005 | 0.082 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-2006 | 0.063 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |
| fleurs-2007 | 0.067 | unavailable: an offline run has no commit latency | 132 MB | 1580 MB |
| fleurs-2008 | 0.050 | unavailable: an offline run has no commit latency | 133 MB | 1580 MB |
| fleurs-2009 | 0.062 | unavailable: an offline run has no commit latency | 134 MB | 1580 MB |

## Items

| Item | Category | WER | CER | N | Sub | Del | Ins |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fleurs-1660 | tagalog | 15.00% | 5.38% | 20 | 2 | 0 | 1 |
| fleurs-1661 | tagalog | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1662 | tagalog | 2.33% | 0.43% | 43 | 1 | 0 | 0 |
| fleurs-1663 | tagalog | 15.38% | 4.88% | 26 | 4 | 0 | 0 |
| fleurs-1664 | tagalog | 8.33% | 1.32% | 24 | 2 | 0 | 0 |
| fleurs-1665 | tagalog | 6.67% | 1.10% | 30 | 2 | 0 | 0 |
| fleurs-1666 | tagalog | 7.14% | 1.26% | 28 | 2 | 0 | 0 |
| fleurs-1667 | tagalog | 0.00% | 0.00% | 38 | 0 | 0 | 0 |
| fleurs-1668 | tagalog | 17.07% | 2.20% | 41 | 5 | 2 | 0 |
| fleurs-1669 | tagalog | 13.04% | 3.73% | 23 | 3 | 0 | 0 |
| fleurs-1670 | tagalog | 13.33% | 3.47% | 60 | 6 | 2 | 0 |
| fleurs-1671 | tagalog | 19.35% | 7.25% | 31 | 6 | 0 | 0 |
| fleurs-1672 | tagalog | 17.39% | 3.17% | 23 | 3 | 1 | 0 |
| fleurs-1673 | tagalog | 22.58% | 3.81% | 31 | 6 | 0 | 1 |
| fleurs-1674 | tagalog | 0.00% | 0.00% | 25 | 0 | 0 | 0 |
| fleurs-1675 | tagalog | 8.00% | 2.17% | 25 | 2 | 0 | 0 |
| fleurs-1676 | tagalog | 4.35% | 0.76% | 23 | 1 | 0 | 0 |
| fleurs-1677 | tagalog | 22.22% | 5.05% | 18 | 4 | 0 | 0 |
| fleurs-1678 | tagalog | 10.53% | 1.79% | 38 | 3 | 1 | 0 |
| fleurs-1679 | tagalog | 27.27% | 6.25% | 11 | 3 | 0 | 0 |
| fleurs-1680 | tagalog | 20.69% | 5.03% | 29 | 5 | 0 | 1 |
| fleurs-1681 | tagalog | 4.65% | 1.12% | 43 | 2 | 0 | 0 |
| fleurs-1682 | tagalog | 30.77% | 24.77% | 39 | 1 | 11 | 0 |
| fleurs-1683 | tagalog | 6.98% | 0.83% | 43 | 2 | 1 | 0 |
| fleurs-1684 | tagalog | 17.39% | 14.66% | 23 | 3 | 0 | 1 |
| fleurs-1685 | tagalog | 32.26% | 6.25% | 31 | 10 | 0 | 0 |
| fleurs-1686 | tagalog | 7.14% | 2.30% | 28 | 2 | 0 | 0 |
| fleurs-1687 | tagalog | 11.11% | 4.92% | 18 | 2 | 0 | 0 |
| fleurs-1688 | tagalog | 0.00% | 0.00% | 44 | 0 | 0 | 0 |
| fleurs-1689 | tagalog | 4.88% | 1.16% | 41 | 2 | 0 | 0 |
| fleurs-1690 | tagalog | 6.82% | 1.88% | 44 | 2 | 1 | 0 |
| fleurs-1691 | tagalog | 11.11% | 2.56% | 27 | 3 | 0 | 0 |
| fleurs-1692 | tagalog | 25.00% | 5.00% | 16 | 4 | 0 | 0 |
| fleurs-1693 | tagalog | 16.67% | 4.51% | 24 | 3 | 0 | 1 |
| fleurs-1694 | tagalog | 3.85% | 1.29% | 26 | 1 | 0 | 0 |
| fleurs-1695 | tagalog | 21.88% | 4.57% | 32 | 3 | 2 | 2 |
| fleurs-1696 | tagalog | 3.57% | 1.16% | 28 | 1 | 0 | 0 |
| fleurs-1697 | tagalog | 9.52% | 2.24% | 21 | 2 | 0 | 0 |
| fleurs-1698 | tagalog | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1699 | tagalog | 6.45% | 2.22% | 31 | 2 | 0 | 0 |
| fleurs-1700 | tagalog | 6.25% | 1.23% | 16 | 1 | 0 | 0 |
| fleurs-1701 | tagalog | 19.05% | 15.09% | 21 | 4 | 0 | 0 |
| fleurs-1702 | tagalog | 13.04% | 5.00% | 23 | 2 | 1 | 0 |
| fleurs-1703 | tagalog | 20.00% | 3.23% | 15 | 1 | 1 | 1 |
| fleurs-1704 | tagalog | 23.81% | 4.69% | 21 | 5 | 0 | 0 |
| fleurs-1705 | tagalog | 15.00% | 4.13% | 20 | 2 | 1 | 0 |
| fleurs-1706 | tagalog | 6.25% | 0.94% | 48 | 2 | 0 | 1 |
| fleurs-1707 | tagalog | 13.64% | 2.21% | 22 | 2 | 0 | 1 |
| fleurs-1708 | tagalog | 17.24% | 5.59% | 29 | 5 | 0 | 0 |
| fleurs-1709 | tagalog | 10.00% | 1.88% | 30 | 2 | 1 | 0 |
| fleurs-1710 | tagalog | 13.79% | 1.81% | 29 | 3 | 1 | 0 |
| fleurs-1711 | tagalog | 0.00% | 0.00% | 42 | 0 | 0 | 0 |
| fleurs-1712 | tagalog | 25.00% | 9.83% | 32 | 6 | 0 | 2 |
| fleurs-1713 | tagalog | 0.00% | 0.00% | 30 | 0 | 0 | 0 |
| fleurs-1714 | tagalog | 2.78% | 0.44% | 36 | 1 | 0 | 0 |
| fleurs-1715 | tagalog | 21.05% | 4.72% | 38 | 6 | 1 | 1 |
| fleurs-1716 | tagalog | 4.84% | 0.79% | 62 | 2 | 1 | 0 |
| fleurs-1717 | tagalog | 0.00% | 0.00% | 29 | 0 | 0 | 0 |
| fleurs-1718 | tagalog | 21.88% | 8.96% | 32 | 4 | 0 | 3 |
| fleurs-1719 | tagalog | 2.86% | 0.92% | 35 | 1 | 0 | 0 |
| fleurs-1720 | tagalog | 10.00% | 1.61% | 20 | 2 | 0 | 0 |
| fleurs-1721 | tagalog | 25.00% | 3.48% | 20 | 3 | 1 | 1 |
| fleurs-1722 | tagalog | 6.06% | 1.34% | 33 | 2 | 0 | 0 |
| fleurs-1723 | tagalog | 13.33% | 5.78% | 30 | 3 | 0 | 1 |
| fleurs-1724 | tagalog | 20.00% | 1.89% | 20 | 2 | 2 | 0 |
| fleurs-1725 | tagalog | 8.11% | 1.63% | 37 | 2 | 1 | 0 |
| fleurs-1726 | tagalog | 14.29% | 3.17% | 35 | 5 | 0 | 0 |
| fleurs-1727 | tagalog | 6.45% | 1.65% | 31 | 2 | 0 | 0 |
| fleurs-1728 | tagalog | 9.09% | 0.89% | 22 | 1 | 1 | 0 |
| fleurs-1729 | tagalog | 16.67% | 3.91% | 48 | 7 | 0 | 1 |
| fleurs-1730 | tagalog | 23.81% | 11.27% | 42 | 5 | 5 | 0 |
| fleurs-1731 | tagalog | 0.00% | 0.00% | 14 | 0 | 0 | 0 |
| fleurs-1732 | tagalog | 35.29% | 24.71% | 34 | 8 | 3 | 1 |
| fleurs-1733 | tagalog | 4.76% | 4.56% | 42 | 1 | 0 | 1 |
| fleurs-1734 | tagalog | 13.89% | 4.65% | 36 | 5 | 0 | 0 |
| fleurs-1735 | tagalog | 18.75% | 4.21% | 64 | 9 | 1 | 2 |
| fleurs-1736 | tagalog | 0.00% | 0.00% | 13 | 0 | 0 | 0 |
| fleurs-1737 | tagalog | 6.25% | 0.99% | 16 | 1 | 0 | 0 |
| fleurs-1738 | tagalog | 23.81% | 4.27% | 21 | 4 | 1 | 0 |
| fleurs-1739 | tagalog | 4.35% | 0.84% | 23 | 1 | 0 | 0 |
| fleurs-1740 | tagalog | 9.52% | 0.94% | 21 | 1 | 1 | 0 |
| fleurs-1741 | tagalog | 10.53% | 0.97% | 19 | 1 | 1 | 0 |
| fleurs-1742 | tagalog | 0.00% | 0.00% | 27 | 0 | 0 | 0 |
| fleurs-1743 | tagalog | 9.80% | 2.61% | 51 | 5 | 0 | 0 |
| fleurs-1744 | tagalog | 5.88% | 0.93% | 17 | 1 | 0 | 0 |
| fleurs-1745 | tagalog | 8.70% | 2.86% | 23 | 2 | 0 | 0 |
| fleurs-1746 | tagalog | 10.53% | 1.74% | 19 | 2 | 0 | 0 |
| fleurs-1747 | tagalog | 0.00% | 0.00% | 9 | 0 | 0 | 0 |
| fleurs-1748 | tagalog | 14.29% | 1.41% | 14 | 1 | 1 | 0 |
| fleurs-1749 | tagalog | 5.88% | 2.19% | 34 | 1 | 1 | 0 |
| fleurs-1750 | tagalog | 0.00% | 0.00% | 15 | 0 | 0 | 0 |
| fleurs-1751 | tagalog | 13.51% | 1.42% | 37 | 3 | 2 | 0 |
| fleurs-1752 | tagalog | 4.55% | 2.34% | 22 | 0 | 0 | 1 |
| fleurs-1753 | tagalog | 10.26% | 2.32% | 39 | 4 | 0 | 0 |
| fleurs-1754 | tagalog | 14.81% | 4.58% | 27 | 3 | 0 | 1 |
| fleurs-1755 | tagalog | 18.18% | 3.08% | 11 | 2 | 0 | 0 |
| fleurs-1756 | tagalog | 8.57% | 2.12% | 35 | 3 | 0 | 0 |
| fleurs-1757 | tagalog | 9.68% | 2.26% | 31 | 1 | 1 | 1 |
| fleurs-1758 | tagalog | 0.00% | 0.00% | 22 | 0 | 0 | 0 |
| fleurs-1759 | tagalog | 25.00% | 6.52% | 48 | 8 | 1 | 3 |
| fleurs-1760 | tagalog | 5.88% | 0.82% | 17 | 1 | 0 | 0 |
| fleurs-1761 | tagalog | 0.00% | 0.00% | 21 | 0 | 0 | 0 |
| fleurs-1762 | tagalog | 5.88% | 2.44% | 17 | 1 | 0 | 0 |
| fleurs-1763 | tagalog | 9.68% | 2.81% | 31 | 2 | 0 | 1 |
| fleurs-1764 | tagalog | 23.53% | 3.64% | 17 | 3 | 0 | 1 |
| fleurs-1765 | tagalog | 11.11% | 4.38% | 18 | 2 | 0 | 0 |
| fleurs-1766 | tagalog | 0.00% | 0.00% | 35 | 0 | 0 | 0 |
| fleurs-1767 | tagalog | 16.00% | 11.31% | 25 | 3 | 1 | 0 |
| fleurs-1768 | tagalog | 3.33% | 1.84% | 30 | 1 | 0 | 0 |
| fleurs-1769 | tagalog | 4.17% | 2.50% | 24 | 1 | 0 | 0 |
| fleurs-1770 | tagalog | 0.00% | 0.00% | 14 | 0 | 0 | 0 |
| fleurs-1771 | tagalog | 3.33% | 0.57% | 30 | 1 | 0 | 0 |
| fleurs-1772 | tagalog | 16.67% | 2.60% | 12 | 1 | 1 | 0 |
| fleurs-1773 | tagalog | 22.22% | 13.87% | 27 | 4 | 0 | 2 |
| fleurs-1774 | tagalog | 4.76% | 1.29% | 42 | 2 | 0 | 0 |
| fleurs-1775 | tagalog | 9.38% | 2.45% | 32 | 3 | 0 | 0 |
| fleurs-1776 | tagalog | 0.00% | 0.00% | 23 | 0 | 0 | 0 |
| fleurs-1777 | tagalog | 10.00% | 2.92% | 30 | 3 | 0 | 0 |
| fleurs-1778 | tagalog | 7.69% | 1.35% | 13 | 1 | 0 | 0 |
| fleurs-1779 | tagalog | 10.53% | 4.46% | 19 | 2 | 0 | 0 |
| fleurs-1780 | tagalog | 12.00% | 3.14% | 25 | 3 | 0 | 0 |
| fleurs-1781 | tagalog | 20.00% | 4.04% | 15 | 2 | 0 | 1 |
| fleurs-1782 | tagalog | 5.00% | 0.93% | 40 | 2 | 0 | 0 |
| fleurs-1783 | tagalog | 22.73% | 4.62% | 22 | 4 | 1 | 0 |
| fleurs-1784 | tagalog | 9.09% | 1.43% | 44 | 3 | 1 | 0 |
| fleurs-1785 | tagalog | 3.70% | 1.24% | 54 | 2 | 0 | 0 |
| fleurs-1786 | tagalog | 3.70% | 0.63% | 27 | 1 | 0 | 0 |
| fleurs-1787 | tagalog | 9.68% | 2.73% | 31 | 3 | 0 | 0 |
| fleurs-1788 | tagalog | 5.26% | 0.43% | 38 | 1 | 1 | 0 |
| fleurs-1789 | tagalog | 0.00% | 0.00% | 25 | 0 | 0 | 0 |
| fleurs-1790 | tagalog | 21.62% | 8.07% | 37 | 5 | 1 | 2 |
| fleurs-1791 | tagalog | 0.00% | 0.00% | 14 | 0 | 0 | 0 |
| fleurs-1792 | tagalog | 5.56% | 1.01% | 18 | 1 | 0 | 0 |
| fleurs-1793 | tagalog | 14.29% | 5.74% | 21 | 3 | 0 | 0 |
| fleurs-1794 | tagalog | 5.26% | 1.53% | 19 | 1 | 0 | 0 |
| fleurs-1795 | tagalog | 8.51% | 1.15% | 47 | 3 | 1 | 0 |
| fleurs-1796 | tagalog | 0.00% | 0.00% | 21 | 0 | 0 | 0 |
| fleurs-1797 | tagalog | 0.00% | 0.00% | 22 | 0 | 0 | 0 |
| fleurs-1798 | tagalog | 16.67% | 3.51% | 30 | 5 | 0 | 0 |
| fleurs-1799 | tagalog | 18.75% | 5.31% | 16 | 3 | 0 | 0 |
| fleurs-1800 | tagalog | 8.70% | 1.32% | 23 | 2 | 0 | 0 |
| fleurs-1801 | tagalog | 5.88% | 2.01% | 34 | 1 | 0 | 1 |
| fleurs-1802 | tagalog | 0.00% | 0.00% | 12 | 0 | 0 | 0 |
| fleurs-1803 | tagalog | 11.54% | 1.94% | 26 | 3 | 0 | 0 |
| fleurs-1804 | tagalog | 16.28% | 4.60% | 43 | 5 | 0 | 2 |
| fleurs-1805 | tagalog | 14.29% | 4.71% | 14 | 2 | 0 | 0 |
| fleurs-1806 | tagalog | 11.90% | 3.14% | 42 | 4 | 0 | 1 |
| fleurs-1807 | tagalog | 7.14% | 1.70% | 28 | 2 | 0 | 0 |
| fleurs-1808 | tagalog | 4.76% | 1.55% | 21 | 1 | 0 | 0 |
| fleurs-1809 | tagalog | 11.76% | 1.93% | 34 | 3 | 0 | 1 |
| fleurs-1810 | tagalog | 5.71% | 0.93% | 35 | 2 | 0 | 0 |
| fleurs-1811 | tagalog | 10.00% | 1.16% | 20 | 1 | 1 | 0 |
| fleurs-1812 | tagalog | 25.71% | 8.26% | 35 | 7 | 1 | 1 |
| fleurs-1813 | tagalog | 20.00% | 8.24% | 30 | 6 | 0 | 0 |
| fleurs-1814 | tagalog | 3.57% | 0.65% | 28 | 1 | 0 | 0 |
| fleurs-1815 | tagalog | 4.76% | 0.75% | 21 | 1 | 0 | 0 |
| fleurs-1816 | tagalog | 13.79% | 1.95% | 29 | 3 | 1 | 0 |
| fleurs-1817 | tagalog | 31.25% | 5.38% | 16 | 3 | 0 | 2 |
| fleurs-1818 | tagalog | 28.57% | 4.31% | 21 | 5 | 1 | 0 |
| fleurs-1819 | tagalog | 3.70% | 0.56% | 27 | 1 | 0 | 0 |
| fleurs-1820 | tagalog | 13.64% | 5.38% | 22 | 3 | 0 | 0 |
| fleurs-1821 | tagalog | 10.53% | 1.67% | 19 | 2 | 0 | 0 |
| fleurs-1822 | tagalog | 31.25% | 5.67% | 32 | 8 | 1 | 1 |
| fleurs-1824 | tagalog | 5.41% | 1.38% | 37 | 2 | 0 | 0 |
| fleurs-1825 | tagalog | 5.88% | 3.74% | 17 | 0 | 0 | 1 |
| fleurs-1826 | tagalog | 26.67% | 3.03% | 15 | 3 | 0 | 1 |
| fleurs-1827 | tagalog | 0.00% | 0.00% | 23 | 0 | 0 | 0 |
| fleurs-1828 | tagalog | 17.39% | 2.88% | 23 | 4 | 0 | 0 |
| fleurs-1829 | tagalog | 0.00% | 0.00% | 35 | 0 | 0 | 0 |
| fleurs-1830 | tagalog | 17.65% | 1.59% | 17 | 2 | 1 | 0 |
| fleurs-1831 | tagalog | 10.00% | 2.25% | 30 | 3 | 0 | 0 |
| fleurs-1832 | tagalog | 19.23% | 10.13% | 26 | 5 | 0 | 0 |
| fleurs-1833 | tagalog | 6.25% | 1.81% | 32 | 2 | 0 | 0 |
| fleurs-1834 | tagalog | 3.70% | 0.66% | 27 | 1 | 0 | 0 |
| fleurs-1835 | tagalog | 12.50% | 2.76% | 32 | 4 | 0 | 0 |
| fleurs-1836 | tagalog | 33.33% | 9.63% | 45 | 12 | 3 | 0 |
| fleurs-1837 | tagalog | 0.00% | 0.00% | 26 | 0 | 0 | 0 |
| fleurs-1838 | tagalog | 16.67% | 4.81% | 18 | 1 | 2 | 0 |
| fleurs-1839 | tagalog | 23.08% | 2.94% | 13 | 2 | 1 | 0 |
| fleurs-1840 | tagalog | 9.38% | 2.35% | 32 | 3 | 0 | 0 |
| fleurs-1841 | tagalog | 0.00% | 0.00% | 27 | 0 | 0 | 0 |
| fleurs-1842 | tagalog | 12.50% | 4.33% | 48 | 5 | 0 | 1 |
| fleurs-1843 | tagalog | 23.33% | 8.11% | 30 | 5 | 0 | 2 |
| fleurs-1844 | tagalog | 9.52% | 3.85% | 21 | 2 | 0 | 0 |
| fleurs-1845 | tagalog | 15.38% | 3.73% | 26 | 4 | 0 | 0 |
| fleurs-1846 | tagalog | 20.83% | 12.98% | 24 | 4 | 0 | 1 |
| fleurs-1847 | tagalog | 10.00% | 3.07% | 30 | 3 | 0 | 0 |
| fleurs-1848 | tagalog | 14.71% | 3.05% | 34 | 4 | 1 | 0 |
| fleurs-1849 | tagalog | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1850 | tagalog | 24.00% | 7.25% | 25 | 4 | 0 | 2 |
| fleurs-1851 | tagalog | 7.14% | 0.65% | 28 | 1 | 0 | 1 |
| fleurs-1852 | tagalog | 9.52% | 4.51% | 63 | 3 | 0 | 3 |
| fleurs-1853 | tagalog | 5.00% | 3.42% | 20 | 1 | 0 | 0 |
| fleurs-1854 | tagalog | 5.26% | 1.87% | 19 | 1 | 0 | 0 |
| fleurs-1855 | tagalog | 30.77% | 22.67% | 39 | 5 | 6 | 1 |
| fleurs-1856 | tagalog | 6.45% | 5.52% | 31 | 1 | 0 | 1 |
| fleurs-1857 | tagalog | 11.11% | 1.26% | 27 | 2 | 1 | 0 |
| fleurs-1858 | tagalog | 8.70% | 2.13% | 23 | 2 | 0 | 0 |
| fleurs-1859 | tagalog | 12.20% | 1.97% | 41 | 4 | 0 | 1 |
| fleurs-1860 | tagalog | 0.00% | 0.00% | 16 | 0 | 0 | 0 |
| fleurs-1861 | tagalog | 4.55% | 0.75% | 22 | 1 | 0 | 0 |
| fleurs-1862 | tagalog | 5.41% | 1.40% | 37 | 2 | 0 | 0 |
| fleurs-1863 | tagalog | 2.38% | 1.65% | 42 | 0 | 1 | 0 |
| fleurs-1864 | tagalog | 13.51% | 3.70% | 37 | 5 | 0 | 0 |
| fleurs-1865 | tagalog | 18.75% | 6.19% | 32 | 5 | 1 | 0 |
| fleurs-1866 | tagalog | 5.00% | 0.81% | 20 | 1 | 0 | 0 |
| fleurs-1867 | tagalog | 10.71% | 3.11% | 28 | 3 | 0 | 0 |
| fleurs-1868 | tagalog | 3.45% | 1.12% | 29 | 1 | 0 | 0 |
| fleurs-1869 | tagalog | 15.62% | 5.73% | 32 | 4 | 0 | 1 |
| fleurs-1870 | tagalog | 17.65% | 6.32% | 17 | 2 | 1 | 0 |
| fleurs-1871 | tagalog | 7.69% | 2.56% | 13 | 1 | 0 | 0 |
| fleurs-1872 | tagalog | 32.26% | 6.63% | 31 | 8 | 1 | 1 |
| fleurs-1873 | tagalog | 0.00% | 0.00% | 26 | 0 | 0 | 0 |
| fleurs-1874 | tagalog | 9.68% | 2.89% | 31 | 3 | 0 | 0 |
| fleurs-1875 | tagalog | 4.55% | 9.82% | 22 | 0 | 1 | 0 |
| fleurs-1876 | tagalog | 16.67% | 2.61% | 18 | 3 | 0 | 0 |
| fleurs-1877 | tagalog | 10.81% | 3.95% | 37 | 3 | 0 | 1 |
| fleurs-1878 | tagalog | 16.67% | 4.61% | 36 | 5 | 1 | 0 |
| fleurs-1879 | tagalog | 0.00% | 0.00% | 18 | 0 | 0 | 0 |
| fleurs-1880 | tagalog | 14.29% | 1.18% | 14 | 1 | 0 | 1 |
| fleurs-1881 | tagalog | 7.14% | 2.21% | 28 | 2 | 0 | 0 |
| fleurs-1882 | tagalog | 15.62% | 3.72% | 32 | 4 | 1 | 0 |
| fleurs-1883 | tagalog | 56.00% | 50.00% | 25 | 4 | 0 | 10 |
| fleurs-1884 | tagalog | 9.09% | 1.95% | 22 | 2 | 0 | 0 |
| fleurs-1885 | tagalog | 45.00% | 46.32% | 20 | 5 | 0 | 4 |
| fleurs-1886 | tagalog | 0.00% | 0.00% | 23 | 0 | 0 | 0 |
| fleurs-1887 | tagalog | 16.67% | 2.99% | 18 | 3 | 0 | 0 |
| fleurs-1888 | tagalog | 31.03% | 26.23% | 29 | 2 | 7 | 0 |
| fleurs-1889 | tagalog | 0.00% | 0.00% | 16 | 0 | 0 | 0 |
| fleurs-1890 | tagalog | 10.00% | 1.36% | 20 | 2 | 0 | 0 |
| fleurs-1891 | tagalog | 43.75% | 12.15% | 16 | 6 | 0 | 1 |
| fleurs-1892 | tagalog | 0.00% | 0.00% | 33 | 0 | 0 | 0 |
| fleurs-1893 | tagalog | 18.75% | 4.42% | 32 | 5 | 1 | 0 |
| fleurs-1894 | tagalog | 0.00% | 0.00% | 19 | 0 | 0 | 0 |
| fleurs-1895 | tagalog | 18.18% | 4.17% | 22 | 4 | 0 | 0 |
| fleurs-1896 | tagalog | 19.05% | 3.91% | 42 | 7 | 1 | 0 |
| fleurs-1897 | tagalog | 17.65% | 6.19% | 17 | 2 | 1 | 0 |
| fleurs-1898 | tagalog | 8.82% | 2.43% | 34 | 2 | 0 | 1 |
| fleurs-1899 | tagalog | 5.13% | 0.90% | 39 | 2 | 0 | 0 |
| fleurs-1900 | tagalog | 4.35% | 2.19% | 23 | 0 | 1 | 0 |
| fleurs-1901 | tagalog | 24.32% | 8.22% | 37 | 7 | 1 | 1 |
| fleurs-1902 | tagalog | 33.33% | 7.46% | 12 | 3 | 0 | 1 |
| fleurs-1903 | tagalog | 4.76% | 0.67% | 21 | 1 | 0 | 0 |
| fleurs-1904 | tagalog | 4.35% | 0.74% | 23 | 1 | 0 | 0 |
| fleurs-1905 | tagalog | 22.22% | 9.73% | 18 | 4 | 0 | 0 |
| fleurs-1906 | tagalog | 21.43% | 8.24% | 14 | 1 | 0 | 2 |
| fleurs-1907 | tagalog | 29.41% | 4.46% | 17 | 4 | 1 | 0 |
| fleurs-1908 | tagalog | 13.33% | 3.30% | 15 | 2 | 0 | 0 |
| fleurs-1909 | tagalog | 7.69% | 1.80% | 26 | 2 | 0 | 0 |
| fleurs-1910 | tagalog | 9.09% | 1.56% | 11 | 1 | 0 | 0 |
| fleurs-1911 | tagalog | 13.33% | 2.13% | 30 | 3 | 0 | 1 |
| fleurs-1912 | tagalog | 0.00% | 0.00% | 20 | 0 | 0 | 0 |
| fleurs-1913 | tagalog | 7.69% | 3.38% | 26 | 2 | 0 | 0 |
| fleurs-1914 | tagalog | 23.53% | 2.52% | 17 | 3 | 0 | 1 |
| fleurs-1915 | tagalog | 11.54% | 3.82% | 26 | 3 | 0 | 0 |
| fleurs-1916 | tagalog | 12.50% | 6.47% | 32 | 2 | 1 | 1 |
| fleurs-1917 | tagalog | 25.00% | 7.56% | 20 | 4 | 0 | 1 |
| fleurs-1918 | tagalog | 12.00% | 1.78% | 25 | 3 | 0 | 0 |
| fleurs-1919 | tagalog | 8.00% | 2.04% | 25 | 2 | 0 | 0 |
| fleurs-1920 | tagalog | 8.00% | 2.58% | 25 | 2 | 0 | 0 |
| fleurs-1921 | tagalog | 8.70% | 2.24% | 23 | 2 | 0 | 0 |
| fleurs-1922 | tagalog | 26.92% | 7.56% | 26 | 7 | 0 | 0 |
| fleurs-1923 | tagalog | 23.91% | 5.68% | 46 | 11 | 0 | 0 |
| fleurs-1924 | tagalog | 40.74% | 31.17% | 27 | 7 | 0 | 4 |
| fleurs-1925 | tagalog | 52.38% | 11.92% | 21 | 8 | 0 | 3 |
| fleurs-1926 | tagalog | 12.50% | 2.91% | 16 | 2 | 0 | 0 |
| fleurs-1927 | tagalog | 4.17% | 0.64% | 24 | 1 | 0 | 0 |
| fleurs-1928 | tagalog | 29.41% | 21.01% | 17 | 4 | 1 | 0 |
| fleurs-1929 | tagalog | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1930 | tagalog | 0.00% | 0.00% | 18 | 0 | 0 | 0 |
| fleurs-1931 | tagalog | 0.00% | 0.00% | 36 | 0 | 0 | 0 |
| fleurs-1932 | tagalog | 12.28% | 2.58% | 57 | 4 | 1 | 2 |
| fleurs-1933 | tagalog | 0.00% | 0.00% | 32 | 0 | 0 | 0 |
| fleurs-1934 | tagalog | 7.41% | 1.32% | 27 | 2 | 0 | 0 |
| fleurs-1935 | tagalog | 25.00% | 3.92% | 16 | 2 | 2 | 0 |
| fleurs-1936 | tagalog | 10.00% | 4.00% | 50 | 4 | 0 | 1 |
| fleurs-1937 | tagalog | 17.39% | 6.53% | 69 | 11 | 1 | 0 |
| fleurs-1938 | tagalog | 8.33% | 3.27% | 24 | 1 | 0 | 1 |
| fleurs-1939 | tagalog | 19.23% | 1.71% | 26 | 3 | 1 | 1 |
| fleurs-1940 | tagalog | 12.12% | 1.95% | 33 | 4 | 0 | 0 |
| fleurs-1941 | tagalog | 18.18% | 7.35% | 11 | 1 | 0 | 1 |
| fleurs-1942 | tagalog | 10.81% | 2.42% | 37 | 3 | 0 | 1 |
| fleurs-1943 | tagalog | 10.71% | 4.12% | 28 | 2 | 0 | 1 |
| fleurs-1944 | tagalog | 0.00% | 0.00% | 28 | 0 | 0 | 0 |
| fleurs-1945 | tagalog | 23.53% | 3.16% | 17 | 3 | 0 | 1 |
| fleurs-1946 | tagalog | 8.33% | 4.37% | 36 | 1 | 1 | 1 |
| fleurs-1947 | tagalog | 4.35% | 1.55% | 23 | 1 | 0 | 0 |
| fleurs-1948 | tagalog | 21.21% | 7.04% | 33 | 5 | 2 | 0 |
| fleurs-1949 | tagalog | 16.67% | 3.00% | 18 | 3 | 0 | 0 |
| fleurs-1950 | tagalog | 2.94% | 2.38% | 34 | 1 | 0 | 0 |
| fleurs-1951 | tagalog | 7.14% | 1.97% | 28 | 2 | 0 | 0 |
| fleurs-1952 | tagalog | 19.35% | 3.28% | 31 | 5 | 0 | 1 |
| fleurs-1953 | tagalog | 9.09% | 2.74% | 11 | 1 | 0 | 0 |
| fleurs-1954 | tagalog | 13.79% | 2.04% | 29 | 4 | 0 | 0 |
| fleurs-1955 | tagalog | 4.76% | 0.91% | 21 | 1 | 0 | 0 |
| fleurs-1956 | tagalog | 3.03% | 1.08% | 33 | 1 | 0 | 0 |
| fleurs-1957 | tagalog | 16.67% | 1.32% | 12 | 1 | 1 | 0 |
| fleurs-1958 | tagalog | 4.35% | 0.86% | 23 | 1 | 0 | 0 |
| fleurs-1959 | tagalog | 21.05% | 3.23% | 19 | 2 | 0 | 2 |
| fleurs-1960 | tagalog | 4.88% | 1.30% | 41 | 2 | 0 | 0 |
| fleurs-1961 | tagalog | 9.09% | 0.99% | 44 | 3 | 0 | 1 |
| fleurs-1962 | tagalog | 10.53% | 6.45% | 19 | 2 | 0 | 0 |
| fleurs-1963 | tagalog | 24.24% | 3.65% | 33 | 5 | 2 | 1 |
| fleurs-1964 | tagalog | 7.41% | 1.81% | 27 | 2 | 0 | 0 |
| fleurs-1965 | tagalog | 3.85% | 1.32% | 26 | 1 | 0 | 0 |
| fleurs-1966 | tagalog | 11.11% | 0.88% | 18 | 1 | 1 | 0 |
| fleurs-1967 | tagalog | 11.43% | 6.17% | 35 | 3 | 0 | 1 |
| fleurs-1968 | tagalog | 2.38% | 0.43% | 42 | 1 | 0 | 0 |
| fleurs-1969 | tagalog | 3.33% | 1.11% | 30 | 1 | 0 | 0 |
| fleurs-1970 | tagalog | 16.13% | 2.66% | 31 | 4 | 1 | 0 |
| fleurs-1971 | tagalog | 17.78% | 2.67% | 45 | 6 | 2 | 0 |
| fleurs-1972 | tagalog | 5.56% | 1.96% | 18 | 1 | 0 | 0 |
| fleurs-1973 | tagalog | 12.50% | 6.12% | 32 | 3 | 1 | 0 |
| fleurs-1974 | tagalog | 23.08% | 2.17% | 13 | 2 | 0 | 1 |
| fleurs-1975 | tagalog | 4.35% | 0.70% | 23 | 1 | 0 | 0 |
| fleurs-1976 | tagalog | 16.67% | 4.93% | 24 | 4 | 0 | 0 |
| fleurs-1977 | tagalog | 9.09% | 3.03% | 22 | 2 | 0 | 0 |
| fleurs-1978 | tagalog | 16.67% | 1.41% | 12 | 1 | 0 | 1 |
| fleurs-1979 | tagalog | 14.29% | 4.50% | 21 | 1 | 0 | 2 |
| fleurs-1980 | tagalog | 20.00% | 12.97% | 25 | 4 | 1 | 0 |
| fleurs-1981 | tagalog | 18.18% | 15.91% | 22 | 2 | 0 | 2 |
| fleurs-1982 | tagalog | 22.73% | 4.23% | 22 | 4 | 0 | 1 |
| fleurs-1983 | tagalog | 5.00% | 0.39% | 40 | 1 | 0 | 1 |
| fleurs-1984 | tagalog | 10.53% | 1.36% | 38 | 3 | 1 | 0 |
| fleurs-1985 | tagalog | 7.32% | 1.26% | 41 | 3 | 0 | 0 |
| fleurs-1986 | tagalog | 31.82% | 15.79% | 22 | 4 | 0 | 3 |
| fleurs-1987 | tagalog | 11.76% | 0.92% | 17 | 1 | 0 | 1 |
| fleurs-1988 | tagalog | 0.00% | 0.00% | 22 | 0 | 0 | 0 |
| fleurs-1989 | tagalog | 18.42% | 9.60% | 38 | 4 | 1 | 2 |
| fleurs-1990 | tagalog | 2.22% | 0.36% | 45 | 1 | 0 | 0 |
| fleurs-1991 | tagalog | 10.53% | 2.33% | 19 | 2 | 0 | 0 |
| fleurs-1992 | tagalog | 19.23% | 3.82% | 26 | 4 | 0 | 1 |
| fleurs-1993 | tagalog | 19.05% | 2.74% | 21 | 3 | 0 | 1 |
| fleurs-1994 | tagalog | 4.55% | 0.82% | 22 | 1 | 0 | 0 |
| fleurs-1995 | tagalog | 20.59% | 4.72% | 34 | 6 | 1 | 0 |
| fleurs-1996 | tagalog | 12.50% | 2.96% | 32 | 4 | 0 | 0 |
| fleurs-1997 | tagalog | 33.33% | 6.40% | 36 | 10 | 1 | 1 |
| fleurs-1998 | tagalog | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1999 | tagalog | 4.00% | 0.66% | 25 | 1 | 0 | 0 |
| fleurs-2000 | tagalog | 3.33% | 0.53% | 30 | 1 | 0 | 0 |
| fleurs-2001 | tagalog | 0.00% | 0.00% | 34 | 0 | 0 | 0 |
| fleurs-2002 | tagalog | 4.17% | 1.47% | 24 | 1 | 0 | 0 |
| fleurs-2003 | tagalog | 5.00% | 0.86% | 20 | 1 | 0 | 0 |
| fleurs-2004 | tagalog | 16.00% | 3.50% | 25 | 4 | 0 | 0 |
| fleurs-2005 | tagalog | 20.00% | 5.38% | 15 | 1 | 1 | 1 |
| fleurs-2006 | tagalog | 8.70% | 1.56% | 23 | 2 | 0 | 0 |
| fleurs-2007 | tagalog | 14.81% | 5.59% | 27 | 3 | 1 | 0 |
| fleurs-2008 | tagalog | 2.33% | 0.39% | 43 | 1 | 0 | 0 |
| fleurs-2009 | tagalog | 2.27% | 0.42% | 44 | 1 | 0 | 0 |

## Utterances

| Item | Utterance | Language | Speaker | Overlap | Time | WER | CER | N | Sub | Del | Ins |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fleurs-1660 | line-1 | tagalog |  |  |  | 15.00% | 5.38% | 20 | 2 | 0 | 1 |
| fleurs-1661 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1662 | line-1 | tagalog |  |  |  | 2.33% | 0.43% | 43 | 1 | 0 | 0 |
| fleurs-1663 | line-1 | tagalog |  |  |  | 15.38% | 4.88% | 26 | 4 | 0 | 0 |
| fleurs-1664 | line-1 | tagalog |  |  |  | 8.33% | 1.32% | 24 | 2 | 0 | 0 |
| fleurs-1665 | line-1 | tagalog |  |  |  | 6.67% | 1.10% | 30 | 2 | 0 | 0 |
| fleurs-1666 | line-1 | tagalog |  |  |  | 7.14% | 1.26% | 28 | 2 | 0 | 0 |
| fleurs-1667 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 38 | 0 | 0 | 0 |
| fleurs-1668 | line-1 | tagalog |  |  |  | 17.07% | 2.20% | 41 | 5 | 2 | 0 |
| fleurs-1669 | line-1 | tagalog |  |  |  | 13.04% | 3.73% | 23 | 3 | 0 | 0 |
| fleurs-1670 | line-1 | tagalog |  |  |  | 13.33% | 3.47% | 60 | 6 | 2 | 0 |
| fleurs-1671 | line-1 | tagalog |  |  |  | 19.35% | 7.25% | 31 | 6 | 0 | 0 |
| fleurs-1672 | line-1 | tagalog |  |  |  | 17.39% | 3.17% | 23 | 3 | 1 | 0 |
| fleurs-1673 | line-1 | tagalog |  |  |  | 22.58% | 3.81% | 31 | 6 | 0 | 1 |
| fleurs-1674 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 25 | 0 | 0 | 0 |
| fleurs-1675 | line-1 | tagalog |  |  |  | 8.00% | 2.17% | 25 | 2 | 0 | 0 |
| fleurs-1676 | line-1 | tagalog |  |  |  | 4.35% | 0.76% | 23 | 1 | 0 | 0 |
| fleurs-1677 | line-1 | tagalog |  |  |  | 22.22% | 5.05% | 18 | 4 | 0 | 0 |
| fleurs-1678 | line-1 | tagalog |  |  |  | 10.53% | 1.79% | 38 | 3 | 1 | 0 |
| fleurs-1679 | line-1 | tagalog |  |  |  | 27.27% | 6.25% | 11 | 3 | 0 | 0 |
| fleurs-1680 | line-1 | tagalog |  |  |  | 20.69% | 5.03% | 29 | 5 | 0 | 1 |
| fleurs-1681 | line-1 | tagalog |  |  |  | 4.65% | 1.12% | 43 | 2 | 0 | 0 |
| fleurs-1682 | line-1 | tagalog |  |  |  | 30.77% | 24.77% | 39 | 1 | 11 | 0 |
| fleurs-1683 | line-1 | tagalog |  |  |  | 6.98% | 0.83% | 43 | 2 | 1 | 0 |
| fleurs-1684 | line-1 | tagalog |  |  |  | 17.39% | 14.66% | 23 | 3 | 0 | 1 |
| fleurs-1685 | line-1 | tagalog |  |  |  | 32.26% | 6.25% | 31 | 10 | 0 | 0 |
| fleurs-1686 | line-1 | tagalog |  |  |  | 7.14% | 2.30% | 28 | 2 | 0 | 0 |
| fleurs-1687 | line-1 | tagalog |  |  |  | 11.11% | 4.92% | 18 | 2 | 0 | 0 |
| fleurs-1688 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 44 | 0 | 0 | 0 |
| fleurs-1689 | line-1 | tagalog |  |  |  | 4.88% | 1.16% | 41 | 2 | 0 | 0 |
| fleurs-1690 | line-1 | tagalog |  |  |  | 6.82% | 1.88% | 44 | 2 | 1 | 0 |
| fleurs-1691 | line-1 | tagalog |  |  |  | 11.11% | 2.56% | 27 | 3 | 0 | 0 |
| fleurs-1692 | line-1 | tagalog |  |  |  | 25.00% | 5.00% | 16 | 4 | 0 | 0 |
| fleurs-1693 | line-1 | tagalog |  |  |  | 16.67% | 4.51% | 24 | 3 | 0 | 1 |
| fleurs-1694 | line-1 | tagalog |  |  |  | 3.85% | 1.29% | 26 | 1 | 0 | 0 |
| fleurs-1695 | line-1 | tagalog |  |  |  | 21.88% | 4.57% | 32 | 3 | 2 | 2 |
| fleurs-1696 | line-1 | tagalog |  |  |  | 3.57% | 1.16% | 28 | 1 | 0 | 0 |
| fleurs-1697 | line-1 | tagalog |  |  |  | 9.52% | 2.24% | 21 | 2 | 0 | 0 |
| fleurs-1698 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1699 | line-1 | tagalog |  |  |  | 6.45% | 2.22% | 31 | 2 | 0 | 0 |
| fleurs-1700 | line-1 | tagalog |  |  |  | 6.25% | 1.23% | 16 | 1 | 0 | 0 |
| fleurs-1701 | line-1 | tagalog |  |  |  | 19.05% | 15.09% | 21 | 4 | 0 | 0 |
| fleurs-1702 | line-1 | tagalog |  |  |  | 13.04% | 5.00% | 23 | 2 | 1 | 0 |
| fleurs-1703 | line-1 | tagalog |  |  |  | 20.00% | 3.23% | 15 | 1 | 1 | 1 |
| fleurs-1704 | line-1 | tagalog |  |  |  | 23.81% | 4.69% | 21 | 5 | 0 | 0 |
| fleurs-1705 | line-1 | tagalog |  |  |  | 15.00% | 4.13% | 20 | 2 | 1 | 0 |
| fleurs-1706 | line-1 | tagalog |  |  |  | 6.25% | 0.94% | 48 | 2 | 0 | 1 |
| fleurs-1707 | line-1 | tagalog |  |  |  | 13.64% | 2.21% | 22 | 2 | 0 | 1 |
| fleurs-1708 | line-1 | tagalog |  |  |  | 17.24% | 5.59% | 29 | 5 | 0 | 0 |
| fleurs-1709 | line-1 | tagalog |  |  |  | 10.00% | 1.88% | 30 | 2 | 1 | 0 |
| fleurs-1710 | line-1 | tagalog |  |  |  | 13.79% | 1.81% | 29 | 3 | 1 | 0 |
| fleurs-1711 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 42 | 0 | 0 | 0 |
| fleurs-1712 | line-1 | tagalog |  |  |  | 25.00% | 9.83% | 32 | 6 | 0 | 2 |
| fleurs-1713 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 30 | 0 | 0 | 0 |
| fleurs-1714 | line-1 | tagalog |  |  |  | 2.78% | 0.44% | 36 | 1 | 0 | 0 |
| fleurs-1715 | line-1 | tagalog |  |  |  | 21.05% | 4.72% | 38 | 6 | 1 | 1 |
| fleurs-1716 | line-1 | tagalog |  |  |  | 4.84% | 0.79% | 62 | 2 | 1 | 0 |
| fleurs-1717 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 29 | 0 | 0 | 0 |
| fleurs-1718 | line-1 | tagalog |  |  |  | 21.88% | 8.96% | 32 | 4 | 0 | 3 |
| fleurs-1719 | line-1 | tagalog |  |  |  | 2.86% | 0.92% | 35 | 1 | 0 | 0 |
| fleurs-1720 | line-1 | tagalog |  |  |  | 10.00% | 1.61% | 20 | 2 | 0 | 0 |
| fleurs-1721 | line-1 | tagalog |  |  |  | 25.00% | 3.48% | 20 | 3 | 1 | 1 |
| fleurs-1722 | line-1 | tagalog |  |  |  | 6.06% | 1.34% | 33 | 2 | 0 | 0 |
| fleurs-1723 | line-1 | tagalog |  |  |  | 13.33% | 5.78% | 30 | 3 | 0 | 1 |
| fleurs-1724 | line-1 | tagalog |  |  |  | 20.00% | 1.89% | 20 | 2 | 2 | 0 |
| fleurs-1725 | line-1 | tagalog |  |  |  | 8.11% | 1.63% | 37 | 2 | 1 | 0 |
| fleurs-1726 | line-1 | tagalog |  |  |  | 14.29% | 3.17% | 35 | 5 | 0 | 0 |
| fleurs-1727 | line-1 | tagalog |  |  |  | 6.45% | 1.65% | 31 | 2 | 0 | 0 |
| fleurs-1728 | line-1 | tagalog |  |  |  | 9.09% | 0.89% | 22 | 1 | 1 | 0 |
| fleurs-1729 | line-1 | tagalog |  |  |  | 16.67% | 3.91% | 48 | 7 | 0 | 1 |
| fleurs-1730 | line-1 | tagalog |  |  |  | 23.81% | 11.27% | 42 | 5 | 5 | 0 |
| fleurs-1731 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 14 | 0 | 0 | 0 |
| fleurs-1732 | line-1 | tagalog |  |  |  | 35.29% | 24.71% | 34 | 8 | 3 | 1 |
| fleurs-1733 | line-1 | tagalog |  |  |  | 4.76% | 4.56% | 42 | 1 | 0 | 1 |
| fleurs-1734 | line-1 | tagalog |  |  |  | 13.89% | 4.65% | 36 | 5 | 0 | 0 |
| fleurs-1735 | line-1 | tagalog |  |  |  | 18.75% | 4.21% | 64 | 9 | 1 | 2 |
| fleurs-1736 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 13 | 0 | 0 | 0 |
| fleurs-1737 | line-1 | tagalog |  |  |  | 6.25% | 0.99% | 16 | 1 | 0 | 0 |
| fleurs-1738 | line-1 | tagalog |  |  |  | 23.81% | 4.27% | 21 | 4 | 1 | 0 |
| fleurs-1739 | line-1 | tagalog |  |  |  | 4.35% | 0.84% | 23 | 1 | 0 | 0 |
| fleurs-1740 | line-1 | tagalog |  |  |  | 9.52% | 0.94% | 21 | 1 | 1 | 0 |
| fleurs-1741 | line-1 | tagalog |  |  |  | 10.53% | 0.97% | 19 | 1 | 1 | 0 |
| fleurs-1742 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 27 | 0 | 0 | 0 |
| fleurs-1743 | line-1 | tagalog |  |  |  | 9.80% | 2.61% | 51 | 5 | 0 | 0 |
| fleurs-1744 | line-1 | tagalog |  |  |  | 5.88% | 0.93% | 17 | 1 | 0 | 0 |
| fleurs-1745 | line-1 | tagalog |  |  |  | 8.70% | 2.86% | 23 | 2 | 0 | 0 |
| fleurs-1746 | line-1 | tagalog |  |  |  | 10.53% | 1.74% | 19 | 2 | 0 | 0 |
| fleurs-1747 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 9 | 0 | 0 | 0 |
| fleurs-1748 | line-1 | tagalog |  |  |  | 14.29% | 1.41% | 14 | 1 | 1 | 0 |
| fleurs-1749 | line-1 | tagalog |  |  |  | 5.88% | 2.19% | 34 | 1 | 1 | 0 |
| fleurs-1750 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 15 | 0 | 0 | 0 |
| fleurs-1751 | line-1 | tagalog |  |  |  | 13.51% | 1.42% | 37 | 3 | 2 | 0 |
| fleurs-1752 | line-1 | tagalog |  |  |  | 4.55% | 2.34% | 22 | 0 | 0 | 1 |
| fleurs-1753 | line-1 | tagalog |  |  |  | 10.26% | 2.32% | 39 | 4 | 0 | 0 |
| fleurs-1754 | line-1 | tagalog |  |  |  | 14.81% | 4.58% | 27 | 3 | 0 | 1 |
| fleurs-1755 | line-1 | tagalog |  |  |  | 18.18% | 3.08% | 11 | 2 | 0 | 0 |
| fleurs-1756 | line-1 | tagalog |  |  |  | 8.57% | 2.12% | 35 | 3 | 0 | 0 |
| fleurs-1757 | line-1 | tagalog |  |  |  | 9.68% | 2.26% | 31 | 1 | 1 | 1 |
| fleurs-1758 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 22 | 0 | 0 | 0 |
| fleurs-1759 | line-1 | tagalog |  |  |  | 25.00% | 6.52% | 48 | 8 | 1 | 3 |
| fleurs-1760 | line-1 | tagalog |  |  |  | 5.88% | 0.82% | 17 | 1 | 0 | 0 |
| fleurs-1761 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 21 | 0 | 0 | 0 |
| fleurs-1762 | line-1 | tagalog |  |  |  | 5.88% | 2.44% | 17 | 1 | 0 | 0 |
| fleurs-1763 | line-1 | tagalog |  |  |  | 9.68% | 2.81% | 31 | 2 | 0 | 1 |
| fleurs-1764 | line-1 | tagalog |  |  |  | 23.53% | 3.64% | 17 | 3 | 0 | 1 |
| fleurs-1765 | line-1 | tagalog |  |  |  | 11.11% | 4.38% | 18 | 2 | 0 | 0 |
| fleurs-1766 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 35 | 0 | 0 | 0 |
| fleurs-1767 | line-1 | tagalog |  |  |  | 16.00% | 11.31% | 25 | 3 | 1 | 0 |
| fleurs-1768 | line-1 | tagalog |  |  |  | 3.33% | 1.84% | 30 | 1 | 0 | 0 |
| fleurs-1769 | line-1 | tagalog |  |  |  | 4.17% | 2.50% | 24 | 1 | 0 | 0 |
| fleurs-1770 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 14 | 0 | 0 | 0 |
| fleurs-1771 | line-1 | tagalog |  |  |  | 3.33% | 0.57% | 30 | 1 | 0 | 0 |
| fleurs-1772 | line-1 | tagalog |  |  |  | 16.67% | 2.60% | 12 | 1 | 1 | 0 |
| fleurs-1773 | line-1 | tagalog |  |  |  | 22.22% | 13.87% | 27 | 4 | 0 | 2 |
| fleurs-1774 | line-1 | tagalog |  |  |  | 4.76% | 1.29% | 42 | 2 | 0 | 0 |
| fleurs-1775 | line-1 | tagalog |  |  |  | 9.38% | 2.45% | 32 | 3 | 0 | 0 |
| fleurs-1776 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 23 | 0 | 0 | 0 |
| fleurs-1777 | line-1 | tagalog |  |  |  | 10.00% | 2.92% | 30 | 3 | 0 | 0 |
| fleurs-1778 | line-1 | tagalog |  |  |  | 7.69% | 1.35% | 13 | 1 | 0 | 0 |
| fleurs-1779 | line-1 | tagalog |  |  |  | 10.53% | 4.46% | 19 | 2 | 0 | 0 |
| fleurs-1780 | line-1 | tagalog |  |  |  | 12.00% | 3.14% | 25 | 3 | 0 | 0 |
| fleurs-1781 | line-1 | tagalog |  |  |  | 20.00% | 4.04% | 15 | 2 | 0 | 1 |
| fleurs-1782 | line-1 | tagalog |  |  |  | 5.00% | 0.93% | 40 | 2 | 0 | 0 |
| fleurs-1783 | line-1 | tagalog |  |  |  | 22.73% | 4.62% | 22 | 4 | 1 | 0 |
| fleurs-1784 | line-1 | tagalog |  |  |  | 9.09% | 1.43% | 44 | 3 | 1 | 0 |
| fleurs-1785 | line-1 | tagalog |  |  |  | 3.70% | 1.24% | 54 | 2 | 0 | 0 |
| fleurs-1786 | line-1 | tagalog |  |  |  | 3.70% | 0.63% | 27 | 1 | 0 | 0 |
| fleurs-1787 | line-1 | tagalog |  |  |  | 9.68% | 2.73% | 31 | 3 | 0 | 0 |
| fleurs-1788 | line-1 | tagalog |  |  |  | 5.26% | 0.43% | 38 | 1 | 1 | 0 |
| fleurs-1789 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 25 | 0 | 0 | 0 |
| fleurs-1790 | line-1 | tagalog |  |  |  | 21.62% | 8.07% | 37 | 5 | 1 | 2 |
| fleurs-1791 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 14 | 0 | 0 | 0 |
| fleurs-1792 | line-1 | tagalog |  |  |  | 5.56% | 1.01% | 18 | 1 | 0 | 0 |
| fleurs-1793 | line-1 | tagalog |  |  |  | 14.29% | 5.74% | 21 | 3 | 0 | 0 |
| fleurs-1794 | line-1 | tagalog |  |  |  | 5.26% | 1.53% | 19 | 1 | 0 | 0 |
| fleurs-1795 | line-1 | tagalog |  |  |  | 8.51% | 1.15% | 47 | 3 | 1 | 0 |
| fleurs-1796 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 21 | 0 | 0 | 0 |
| fleurs-1797 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 22 | 0 | 0 | 0 |
| fleurs-1798 | line-1 | tagalog |  |  |  | 16.67% | 3.51% | 30 | 5 | 0 | 0 |
| fleurs-1799 | line-1 | tagalog |  |  |  | 18.75% | 5.31% | 16 | 3 | 0 | 0 |
| fleurs-1800 | line-1 | tagalog |  |  |  | 8.70% | 1.32% | 23 | 2 | 0 | 0 |
| fleurs-1801 | line-1 | tagalog |  |  |  | 5.88% | 2.01% | 34 | 1 | 0 | 1 |
| fleurs-1802 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 12 | 0 | 0 | 0 |
| fleurs-1803 | line-1 | tagalog |  |  |  | 11.54% | 1.94% | 26 | 3 | 0 | 0 |
| fleurs-1804 | line-1 | tagalog |  |  |  | 16.28% | 4.60% | 43 | 5 | 0 | 2 |
| fleurs-1805 | line-1 | tagalog |  |  |  | 14.29% | 4.71% | 14 | 2 | 0 | 0 |
| fleurs-1806 | line-1 | tagalog |  |  |  | 11.90% | 3.14% | 42 | 4 | 0 | 1 |
| fleurs-1807 | line-1 | tagalog |  |  |  | 7.14% | 1.70% | 28 | 2 | 0 | 0 |
| fleurs-1808 | line-1 | tagalog |  |  |  | 4.76% | 1.55% | 21 | 1 | 0 | 0 |
| fleurs-1809 | line-1 | tagalog |  |  |  | 11.76% | 1.93% | 34 | 3 | 0 | 1 |
| fleurs-1810 | line-1 | tagalog |  |  |  | 5.71% | 0.93% | 35 | 2 | 0 | 0 |
| fleurs-1811 | line-1 | tagalog |  |  |  | 10.00% | 1.16% | 20 | 1 | 1 | 0 |
| fleurs-1812 | line-1 | tagalog |  |  |  | 25.71% | 8.26% | 35 | 7 | 1 | 1 |
| fleurs-1813 | line-1 | tagalog |  |  |  | 20.00% | 8.24% | 30 | 6 | 0 | 0 |
| fleurs-1814 | line-1 | tagalog |  |  |  | 3.57% | 0.65% | 28 | 1 | 0 | 0 |
| fleurs-1815 | line-1 | tagalog |  |  |  | 4.76% | 0.75% | 21 | 1 | 0 | 0 |
| fleurs-1816 | line-1 | tagalog |  |  |  | 13.79% | 1.95% | 29 | 3 | 1 | 0 |
| fleurs-1817 | line-1 | tagalog |  |  |  | 31.25% | 5.38% | 16 | 3 | 0 | 2 |
| fleurs-1818 | line-1 | tagalog |  |  |  | 28.57% | 4.31% | 21 | 5 | 1 | 0 |
| fleurs-1819 | line-1 | tagalog |  |  |  | 3.70% | 0.56% | 27 | 1 | 0 | 0 |
| fleurs-1820 | line-1 | tagalog |  |  |  | 13.64% | 5.38% | 22 | 3 | 0 | 0 |
| fleurs-1821 | line-1 | tagalog |  |  |  | 10.53% | 1.67% | 19 | 2 | 0 | 0 |
| fleurs-1822 | line-1 | tagalog |  |  |  | 31.25% | 5.67% | 32 | 8 | 1 | 1 |
| fleurs-1824 | line-1 | tagalog |  |  |  | 5.41% | 1.38% | 37 | 2 | 0 | 0 |
| fleurs-1825 | line-1 | tagalog |  |  |  | 5.88% | 3.74% | 17 | 0 | 0 | 1 |
| fleurs-1826 | line-1 | tagalog |  |  |  | 26.67% | 3.03% | 15 | 3 | 0 | 1 |
| fleurs-1827 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 23 | 0 | 0 | 0 |
| fleurs-1828 | line-1 | tagalog |  |  |  | 17.39% | 2.88% | 23 | 4 | 0 | 0 |
| fleurs-1829 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 35 | 0 | 0 | 0 |
| fleurs-1830 | line-1 | tagalog |  |  |  | 17.65% | 1.59% | 17 | 2 | 1 | 0 |
| fleurs-1831 | line-1 | tagalog |  |  |  | 10.00% | 2.25% | 30 | 3 | 0 | 0 |
| fleurs-1832 | line-1 | tagalog |  |  |  | 19.23% | 10.13% | 26 | 5 | 0 | 0 |
| fleurs-1833 | line-1 | tagalog |  |  |  | 6.25% | 1.81% | 32 | 2 | 0 | 0 |
| fleurs-1834 | line-1 | tagalog |  |  |  | 3.70% | 0.66% | 27 | 1 | 0 | 0 |
| fleurs-1835 | line-1 | tagalog |  |  |  | 12.50% | 2.76% | 32 | 4 | 0 | 0 |
| fleurs-1836 | line-1 | tagalog |  |  |  | 33.33% | 9.63% | 45 | 12 | 3 | 0 |
| fleurs-1837 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 26 | 0 | 0 | 0 |
| fleurs-1838 | line-1 | tagalog |  |  |  | 16.67% | 4.81% | 18 | 1 | 2 | 0 |
| fleurs-1839 | line-1 | tagalog |  |  |  | 23.08% | 2.94% | 13 | 2 | 1 | 0 |
| fleurs-1840 | line-1 | tagalog |  |  |  | 9.38% | 2.35% | 32 | 3 | 0 | 0 |
| fleurs-1841 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 27 | 0 | 0 | 0 |
| fleurs-1842 | line-1 | tagalog |  |  |  | 12.50% | 4.33% | 48 | 5 | 0 | 1 |
| fleurs-1843 | line-1 | tagalog |  |  |  | 23.33% | 8.11% | 30 | 5 | 0 | 2 |
| fleurs-1844 | line-1 | tagalog |  |  |  | 9.52% | 3.85% | 21 | 2 | 0 | 0 |
| fleurs-1845 | line-1 | tagalog |  |  |  | 15.38% | 3.73% | 26 | 4 | 0 | 0 |
| fleurs-1846 | line-1 | tagalog |  |  |  | 20.83% | 12.98% | 24 | 4 | 0 | 1 |
| fleurs-1847 | line-1 | tagalog |  |  |  | 10.00% | 3.07% | 30 | 3 | 0 | 0 |
| fleurs-1848 | line-1 | tagalog |  |  |  | 14.71% | 3.05% | 34 | 4 | 1 | 0 |
| fleurs-1849 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1850 | line-1 | tagalog |  |  |  | 24.00% | 7.25% | 25 | 4 | 0 | 2 |
| fleurs-1851 | line-1 | tagalog |  |  |  | 7.14% | 0.65% | 28 | 1 | 0 | 1 |
| fleurs-1852 | line-1 | tagalog |  |  |  | 9.52% | 4.51% | 63 | 3 | 0 | 3 |
| fleurs-1853 | line-1 | tagalog |  |  |  | 5.00% | 3.42% | 20 | 1 | 0 | 0 |
| fleurs-1854 | line-1 | tagalog |  |  |  | 5.26% | 1.87% | 19 | 1 | 0 | 0 |
| fleurs-1855 | line-1 | tagalog |  |  |  | 30.77% | 22.67% | 39 | 5 | 6 | 1 |
| fleurs-1856 | line-1 | tagalog |  |  |  | 6.45% | 5.52% | 31 | 1 | 0 | 1 |
| fleurs-1857 | line-1 | tagalog |  |  |  | 11.11% | 1.26% | 27 | 2 | 1 | 0 |
| fleurs-1858 | line-1 | tagalog |  |  |  | 8.70% | 2.13% | 23 | 2 | 0 | 0 |
| fleurs-1859 | line-1 | tagalog |  |  |  | 12.20% | 1.97% | 41 | 4 | 0 | 1 |
| fleurs-1860 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 16 | 0 | 0 | 0 |
| fleurs-1861 | line-1 | tagalog |  |  |  | 4.55% | 0.75% | 22 | 1 | 0 | 0 |
| fleurs-1862 | line-1 | tagalog |  |  |  | 5.41% | 1.40% | 37 | 2 | 0 | 0 |
| fleurs-1863 | line-1 | tagalog |  |  |  | 2.38% | 1.65% | 42 | 0 | 1 | 0 |
| fleurs-1864 | line-1 | tagalog |  |  |  | 13.51% | 3.70% | 37 | 5 | 0 | 0 |
| fleurs-1865 | line-1 | tagalog |  |  |  | 18.75% | 6.19% | 32 | 5 | 1 | 0 |
| fleurs-1866 | line-1 | tagalog |  |  |  | 5.00% | 0.81% | 20 | 1 | 0 | 0 |
| fleurs-1867 | line-1 | tagalog |  |  |  | 10.71% | 3.11% | 28 | 3 | 0 | 0 |
| fleurs-1868 | line-1 | tagalog |  |  |  | 3.45% | 1.12% | 29 | 1 | 0 | 0 |
| fleurs-1869 | line-1 | tagalog |  |  |  | 15.62% | 5.73% | 32 | 4 | 0 | 1 |
| fleurs-1870 | line-1 | tagalog |  |  |  | 17.65% | 6.32% | 17 | 2 | 1 | 0 |
| fleurs-1871 | line-1 | tagalog |  |  |  | 7.69% | 2.56% | 13 | 1 | 0 | 0 |
| fleurs-1872 | line-1 | tagalog |  |  |  | 32.26% | 6.63% | 31 | 8 | 1 | 1 |
| fleurs-1873 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 26 | 0 | 0 | 0 |
| fleurs-1874 | line-1 | tagalog |  |  |  | 9.68% | 2.89% | 31 | 3 | 0 | 0 |
| fleurs-1875 | line-1 | tagalog |  |  |  | 4.55% | 9.82% | 22 | 0 | 1 | 0 |
| fleurs-1876 | line-1 | tagalog |  |  |  | 16.67% | 2.61% | 18 | 3 | 0 | 0 |
| fleurs-1877 | line-1 | tagalog |  |  |  | 10.81% | 3.95% | 37 | 3 | 0 | 1 |
| fleurs-1878 | line-1 | tagalog |  |  |  | 16.67% | 4.61% | 36 | 5 | 1 | 0 |
| fleurs-1879 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 18 | 0 | 0 | 0 |
| fleurs-1880 | line-1 | tagalog |  |  |  | 14.29% | 1.18% | 14 | 1 | 0 | 1 |
| fleurs-1881 | line-1 | tagalog |  |  |  | 7.14% | 2.21% | 28 | 2 | 0 | 0 |
| fleurs-1882 | line-1 | tagalog |  |  |  | 15.62% | 3.72% | 32 | 4 | 1 | 0 |
| fleurs-1883 | line-1 | tagalog |  |  |  | 56.00% | 50.00% | 25 | 4 | 0 | 10 |
| fleurs-1884 | line-1 | tagalog |  |  |  | 9.09% | 1.95% | 22 | 2 | 0 | 0 |
| fleurs-1885 | line-1 | tagalog |  |  |  | 45.00% | 46.32% | 20 | 5 | 0 | 4 |
| fleurs-1886 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 23 | 0 | 0 | 0 |
| fleurs-1887 | line-1 | tagalog |  |  |  | 16.67% | 2.99% | 18 | 3 | 0 | 0 |
| fleurs-1888 | line-1 | tagalog |  |  |  | 31.03% | 26.23% | 29 | 2 | 7 | 0 |
| fleurs-1889 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 16 | 0 | 0 | 0 |
| fleurs-1890 | line-1 | tagalog |  |  |  | 10.00% | 1.36% | 20 | 2 | 0 | 0 |
| fleurs-1891 | line-1 | tagalog |  |  |  | 43.75% | 12.15% | 16 | 6 | 0 | 1 |
| fleurs-1892 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 33 | 0 | 0 | 0 |
| fleurs-1893 | line-1 | tagalog |  |  |  | 18.75% | 4.42% | 32 | 5 | 1 | 0 |
| fleurs-1894 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 19 | 0 | 0 | 0 |
| fleurs-1895 | line-1 | tagalog |  |  |  | 18.18% | 4.17% | 22 | 4 | 0 | 0 |
| fleurs-1896 | line-1 | tagalog |  |  |  | 19.05% | 3.91% | 42 | 7 | 1 | 0 |
| fleurs-1897 | line-1 | tagalog |  |  |  | 17.65% | 6.19% | 17 | 2 | 1 | 0 |
| fleurs-1898 | line-1 | tagalog |  |  |  | 8.82% | 2.43% | 34 | 2 | 0 | 1 |
| fleurs-1899 | line-1 | tagalog |  |  |  | 5.13% | 0.90% | 39 | 2 | 0 | 0 |
| fleurs-1900 | line-1 | tagalog |  |  |  | 4.35% | 2.19% | 23 | 0 | 1 | 0 |
| fleurs-1901 | line-1 | tagalog |  |  |  | 24.32% | 8.22% | 37 | 7 | 1 | 1 |
| fleurs-1902 | line-1 | tagalog |  |  |  | 33.33% | 7.46% | 12 | 3 | 0 | 1 |
| fleurs-1903 | line-1 | tagalog |  |  |  | 4.76% | 0.67% | 21 | 1 | 0 | 0 |
| fleurs-1904 | line-1 | tagalog |  |  |  | 4.35% | 0.74% | 23 | 1 | 0 | 0 |
| fleurs-1905 | line-1 | tagalog |  |  |  | 22.22% | 9.73% | 18 | 4 | 0 | 0 |
| fleurs-1906 | line-1 | tagalog |  |  |  | 21.43% | 8.24% | 14 | 1 | 0 | 2 |
| fleurs-1907 | line-1 | tagalog |  |  |  | 29.41% | 4.46% | 17 | 4 | 1 | 0 |
| fleurs-1908 | line-1 | tagalog |  |  |  | 13.33% | 3.30% | 15 | 2 | 0 | 0 |
| fleurs-1909 | line-1 | tagalog |  |  |  | 7.69% | 1.80% | 26 | 2 | 0 | 0 |
| fleurs-1910 | line-1 | tagalog |  |  |  | 9.09% | 1.56% | 11 | 1 | 0 | 0 |
| fleurs-1911 | line-1 | tagalog |  |  |  | 13.33% | 2.13% | 30 | 3 | 0 | 1 |
| fleurs-1912 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 20 | 0 | 0 | 0 |
| fleurs-1913 | line-1 | tagalog |  |  |  | 7.69% | 3.38% | 26 | 2 | 0 | 0 |
| fleurs-1914 | line-1 | tagalog |  |  |  | 23.53% | 2.52% | 17 | 3 | 0 | 1 |
| fleurs-1915 | line-1 | tagalog |  |  |  | 11.54% | 3.82% | 26 | 3 | 0 | 0 |
| fleurs-1916 | line-1 | tagalog |  |  |  | 12.50% | 6.47% | 32 | 2 | 1 | 1 |
| fleurs-1917 | line-1 | tagalog |  |  |  | 25.00% | 7.56% | 20 | 4 | 0 | 1 |
| fleurs-1918 | line-1 | tagalog |  |  |  | 12.00% | 1.78% | 25 | 3 | 0 | 0 |
| fleurs-1919 | line-1 | tagalog |  |  |  | 8.00% | 2.04% | 25 | 2 | 0 | 0 |
| fleurs-1920 | line-1 | tagalog |  |  |  | 8.00% | 2.58% | 25 | 2 | 0 | 0 |
| fleurs-1921 | line-1 | tagalog |  |  |  | 8.70% | 2.24% | 23 | 2 | 0 | 0 |
| fleurs-1922 | line-1 | tagalog |  |  |  | 26.92% | 7.56% | 26 | 7 | 0 | 0 |
| fleurs-1923 | line-1 | tagalog |  |  |  | 23.91% | 5.68% | 46 | 11 | 0 | 0 |
| fleurs-1924 | line-1 | tagalog |  |  |  | 40.74% | 31.17% | 27 | 7 | 0 | 4 |
| fleurs-1925 | line-1 | tagalog |  |  |  | 52.38% | 11.92% | 21 | 8 | 0 | 3 |
| fleurs-1926 | line-1 | tagalog |  |  |  | 12.50% | 2.91% | 16 | 2 | 0 | 0 |
| fleurs-1927 | line-1 | tagalog |  |  |  | 4.17% | 0.64% | 24 | 1 | 0 | 0 |
| fleurs-1928 | line-1 | tagalog |  |  |  | 29.41% | 21.01% | 17 | 4 | 1 | 0 |
| fleurs-1929 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1930 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 18 | 0 | 0 | 0 |
| fleurs-1931 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 36 | 0 | 0 | 0 |
| fleurs-1932 | line-1 | tagalog |  |  |  | 12.28% | 2.58% | 57 | 4 | 1 | 2 |
| fleurs-1933 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 32 | 0 | 0 | 0 |
| fleurs-1934 | line-1 | tagalog |  |  |  | 7.41% | 1.32% | 27 | 2 | 0 | 0 |
| fleurs-1935 | line-1 | tagalog |  |  |  | 25.00% | 3.92% | 16 | 2 | 2 | 0 |
| fleurs-1936 | line-1 | tagalog |  |  |  | 10.00% | 4.00% | 50 | 4 | 0 | 1 |
| fleurs-1937 | line-1 | tagalog |  |  |  | 17.39% | 6.53% | 69 | 11 | 1 | 0 |
| fleurs-1938 | line-1 | tagalog |  |  |  | 8.33% | 3.27% | 24 | 1 | 0 | 1 |
| fleurs-1939 | line-1 | tagalog |  |  |  | 19.23% | 1.71% | 26 | 3 | 1 | 1 |
| fleurs-1940 | line-1 | tagalog |  |  |  | 12.12% | 1.95% | 33 | 4 | 0 | 0 |
| fleurs-1941 | line-1 | tagalog |  |  |  | 18.18% | 7.35% | 11 | 1 | 0 | 1 |
| fleurs-1942 | line-1 | tagalog |  |  |  | 10.81% | 2.42% | 37 | 3 | 0 | 1 |
| fleurs-1943 | line-1 | tagalog |  |  |  | 10.71% | 4.12% | 28 | 2 | 0 | 1 |
| fleurs-1944 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 28 | 0 | 0 | 0 |
| fleurs-1945 | line-1 | tagalog |  |  |  | 23.53% | 3.16% | 17 | 3 | 0 | 1 |
| fleurs-1946 | line-1 | tagalog |  |  |  | 8.33% | 4.37% | 36 | 1 | 1 | 1 |
| fleurs-1947 | line-1 | tagalog |  |  |  | 4.35% | 1.55% | 23 | 1 | 0 | 0 |
| fleurs-1948 | line-1 | tagalog |  |  |  | 21.21% | 7.04% | 33 | 5 | 2 | 0 |
| fleurs-1949 | line-1 | tagalog |  |  |  | 16.67% | 3.00% | 18 | 3 | 0 | 0 |
| fleurs-1950 | line-1 | tagalog |  |  |  | 2.94% | 2.38% | 34 | 1 | 0 | 0 |
| fleurs-1951 | line-1 | tagalog |  |  |  | 7.14% | 1.97% | 28 | 2 | 0 | 0 |
| fleurs-1952 | line-1 | tagalog |  |  |  | 19.35% | 3.28% | 31 | 5 | 0 | 1 |
| fleurs-1953 | line-1 | tagalog |  |  |  | 9.09% | 2.74% | 11 | 1 | 0 | 0 |
| fleurs-1954 | line-1 | tagalog |  |  |  | 13.79% | 2.04% | 29 | 4 | 0 | 0 |
| fleurs-1955 | line-1 | tagalog |  |  |  | 4.76% | 0.91% | 21 | 1 | 0 | 0 |
| fleurs-1956 | line-1 | tagalog |  |  |  | 3.03% | 1.08% | 33 | 1 | 0 | 0 |
| fleurs-1957 | line-1 | tagalog |  |  |  | 16.67% | 1.32% | 12 | 1 | 1 | 0 |
| fleurs-1958 | line-1 | tagalog |  |  |  | 4.35% | 0.86% | 23 | 1 | 0 | 0 |
| fleurs-1959 | line-1 | tagalog |  |  |  | 21.05% | 3.23% | 19 | 2 | 0 | 2 |
| fleurs-1960 | line-1 | tagalog |  |  |  | 4.88% | 1.30% | 41 | 2 | 0 | 0 |
| fleurs-1961 | line-1 | tagalog |  |  |  | 9.09% | 0.99% | 44 | 3 | 0 | 1 |
| fleurs-1962 | line-1 | tagalog |  |  |  | 10.53% | 6.45% | 19 | 2 | 0 | 0 |
| fleurs-1963 | line-1 | tagalog |  |  |  | 24.24% | 3.65% | 33 | 5 | 2 | 1 |
| fleurs-1964 | line-1 | tagalog |  |  |  | 7.41% | 1.81% | 27 | 2 | 0 | 0 |
| fleurs-1965 | line-1 | tagalog |  |  |  | 3.85% | 1.32% | 26 | 1 | 0 | 0 |
| fleurs-1966 | line-1 | tagalog |  |  |  | 11.11% | 0.88% | 18 | 1 | 1 | 0 |
| fleurs-1967 | line-1 | tagalog |  |  |  | 11.43% | 6.17% | 35 | 3 | 0 | 1 |
| fleurs-1968 | line-1 | tagalog |  |  |  | 2.38% | 0.43% | 42 | 1 | 0 | 0 |
| fleurs-1969 | line-1 | tagalog |  |  |  | 3.33% | 1.11% | 30 | 1 | 0 | 0 |
| fleurs-1970 | line-1 | tagalog |  |  |  | 16.13% | 2.66% | 31 | 4 | 1 | 0 |
| fleurs-1971 | line-1 | tagalog |  |  |  | 17.78% | 2.67% | 45 | 6 | 2 | 0 |
| fleurs-1972 | line-1 | tagalog |  |  |  | 5.56% | 1.96% | 18 | 1 | 0 | 0 |
| fleurs-1973 | line-1 | tagalog |  |  |  | 12.50% | 6.12% | 32 | 3 | 1 | 0 |
| fleurs-1974 | line-1 | tagalog |  |  |  | 23.08% | 2.17% | 13 | 2 | 0 | 1 |
| fleurs-1975 | line-1 | tagalog |  |  |  | 4.35% | 0.70% | 23 | 1 | 0 | 0 |
| fleurs-1976 | line-1 | tagalog |  |  |  | 16.67% | 4.93% | 24 | 4 | 0 | 0 |
| fleurs-1977 | line-1 | tagalog |  |  |  | 9.09% | 3.03% | 22 | 2 | 0 | 0 |
| fleurs-1978 | line-1 | tagalog |  |  |  | 16.67% | 1.41% | 12 | 1 | 0 | 1 |
| fleurs-1979 | line-1 | tagalog |  |  |  | 14.29% | 4.50% | 21 | 1 | 0 | 2 |
| fleurs-1980 | line-1 | tagalog |  |  |  | 20.00% | 12.97% | 25 | 4 | 1 | 0 |
| fleurs-1981 | line-1 | tagalog |  |  |  | 18.18% | 15.91% | 22 | 2 | 0 | 2 |
| fleurs-1982 | line-1 | tagalog |  |  |  | 22.73% | 4.23% | 22 | 4 | 0 | 1 |
| fleurs-1983 | line-1 | tagalog |  |  |  | 5.00% | 0.39% | 40 | 1 | 0 | 1 |
| fleurs-1984 | line-1 | tagalog |  |  |  | 10.53% | 1.36% | 38 | 3 | 1 | 0 |
| fleurs-1985 | line-1 | tagalog |  |  |  | 7.32% | 1.26% | 41 | 3 | 0 | 0 |
| fleurs-1986 | line-1 | tagalog |  |  |  | 31.82% | 15.79% | 22 | 4 | 0 | 3 |
| fleurs-1987 | line-1 | tagalog |  |  |  | 11.76% | 0.92% | 17 | 1 | 0 | 1 |
| fleurs-1988 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 22 | 0 | 0 | 0 |
| fleurs-1989 | line-1 | tagalog |  |  |  | 18.42% | 9.60% | 38 | 4 | 1 | 2 |
| fleurs-1990 | line-1 | tagalog |  |  |  | 2.22% | 0.36% | 45 | 1 | 0 | 0 |
| fleurs-1991 | line-1 | tagalog |  |  |  | 10.53% | 2.33% | 19 | 2 | 0 | 0 |
| fleurs-1992 | line-1 | tagalog |  |  |  | 19.23% | 3.82% | 26 | 4 | 0 | 1 |
| fleurs-1993 | line-1 | tagalog |  |  |  | 19.05% | 2.74% | 21 | 3 | 0 | 1 |
| fleurs-1994 | line-1 | tagalog |  |  |  | 4.55% | 0.82% | 22 | 1 | 0 | 0 |
| fleurs-1995 | line-1 | tagalog |  |  |  | 20.59% | 4.72% | 34 | 6 | 1 | 0 |
| fleurs-1996 | line-1 | tagalog |  |  |  | 12.50% | 2.96% | 32 | 4 | 0 | 0 |
| fleurs-1997 | line-1 | tagalog |  |  |  | 33.33% | 6.40% | 36 | 10 | 1 | 1 |
| fleurs-1998 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1999 | line-1 | tagalog |  |  |  | 4.00% | 0.66% | 25 | 1 | 0 | 0 |
| fleurs-2000 | line-1 | tagalog |  |  |  | 3.33% | 0.53% | 30 | 1 | 0 | 0 |
| fleurs-2001 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 34 | 0 | 0 | 0 |
| fleurs-2002 | line-1 | tagalog |  |  |  | 4.17% | 1.47% | 24 | 1 | 0 | 0 |
| fleurs-2003 | line-1 | tagalog |  |  |  | 5.00% | 0.86% | 20 | 1 | 0 | 0 |
| fleurs-2004 | line-1 | tagalog |  |  |  | 16.00% | 3.50% | 25 | 4 | 0 | 0 |
| fleurs-2005 | line-1 | tagalog |  |  |  | 20.00% | 5.38% | 15 | 1 | 1 | 1 |
| fleurs-2006 | line-1 | tagalog |  |  |  | 8.70% | 1.56% | 23 | 2 | 0 | 0 |
| fleurs-2007 | line-1 | tagalog |  |  |  | 14.81% | 5.59% | 27 | 3 | 1 | 0 |
| fleurs-2008 | line-1 | tagalog |  |  |  | 2.33% | 0.39% | 43 | 1 | 0 | 0 |
| fleurs-2009 | line-1 | tagalog |  |  |  | 2.27% | 0.42% | 44 | 1 | 0 | 0 |

The raw reference and hypothesis of each item are in the JSON report, unchanged.

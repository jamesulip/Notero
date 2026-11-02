# ASR evaluation: best

| | |
| --- | --- |
| Corpus | `fleurs-fil_ph-test-onepersentence-seed7` |
| Items scored | 349 of 349 |
| Configuration | `notero-eval-v1` (schema 1), fingerprint `96fdf032732a3b31` |
| Scoring policy | `notero-standard` v1, fingerprint `5c0946fada2f868b` |
| System | best |
| Model | `openai_whisper-large-v3_turbo` |
| Model revision | `0f63a7800b00dd0226abd051b906c246e1907482` |
| Build | `5f34fbcffa1a756b2dcdc9cf1fc20ecb53970c78` |
| Hardware | Mac14,12 · 10 cores · macOS 26.6, 16 GB |
| Inference | mode offline, language tl, diarization off, roomMode false, styleHint false |

Policy: Unicode NFKC, case folded, diacritics kept, punctuation removed, hyphens split words, intra-word apostrophes kept, contractions as written.

## Accuracy

| Metric | Value | 95% interval | N | Sub | Del | Ins |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| WER | 11.35% | 10.41% to 12.34% | 9613 | 842 | 124 | 125 |
| CER | 3.45% | 2.97% to 3.98% | 57364 | 632 | 796 | 549 |

Interval: percentile bootstrap of the pooled rate ΣE/ΣN, type-7 quantiles, SplitMix64; 2000 resamples of 349 utterances, seed 20261102, stratified by utterance language class.

### By utterance language

| Stratum | Utterances | WER | CER | N | Sub | Del | Ins |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| tagalog | 349 | 11.35% | 3.45% | 9613 | 842 | 124 | 125 |

### By word language

Covers 349 of 349 scored items: fleurs-1660, fleurs-1661, fleurs-1662, fleurs-1663, fleurs-1664, fleurs-1665, fleurs-1666, fleurs-1667, fleurs-1668, fleurs-1669, fleurs-1670, fleurs-1671, fleurs-1672, fleurs-1673, fleurs-1674, fleurs-1675, fleurs-1676, fleurs-1677, fleurs-1678, fleurs-1679, fleurs-1680, fleurs-1681, fleurs-1682, fleurs-1683, fleurs-1684, fleurs-1685, fleurs-1686, fleurs-1687, fleurs-1688, fleurs-1689, fleurs-1690, fleurs-1691, fleurs-1692, fleurs-1693, fleurs-1694, fleurs-1695, fleurs-1696, fleurs-1697, fleurs-1698, fleurs-1699, fleurs-1700, fleurs-1701, fleurs-1702, fleurs-1703, fleurs-1704, fleurs-1705, fleurs-1706, fleurs-1707, fleurs-1708, fleurs-1709, fleurs-1710, fleurs-1711, fleurs-1712, fleurs-1713, fleurs-1714, fleurs-1715, fleurs-1716, fleurs-1717, fleurs-1718, fleurs-1719, fleurs-1720, fleurs-1721, fleurs-1722, fleurs-1723, fleurs-1724, fleurs-1725, fleurs-1726, fleurs-1727, fleurs-1728, fleurs-1729, fleurs-1730, fleurs-1731, fleurs-1732, fleurs-1733, fleurs-1734, fleurs-1735, fleurs-1736, fleurs-1737, fleurs-1738, fleurs-1739, fleurs-1740, fleurs-1741, fleurs-1742, fleurs-1743, fleurs-1744, fleurs-1745, fleurs-1746, fleurs-1747, fleurs-1748, fleurs-1749, fleurs-1750, fleurs-1751, fleurs-1752, fleurs-1753, fleurs-1754, fleurs-1755, fleurs-1756, fleurs-1757, fleurs-1758, fleurs-1759, fleurs-1760, fleurs-1761, fleurs-1762, fleurs-1763, fleurs-1764, fleurs-1765, fleurs-1766, fleurs-1767, fleurs-1768, fleurs-1769, fleurs-1770, fleurs-1771, fleurs-1772, fleurs-1773, fleurs-1774, fleurs-1775, fleurs-1776, fleurs-1777, fleurs-1778, fleurs-1779, fleurs-1780, fleurs-1781, fleurs-1782, fleurs-1783, fleurs-1784, fleurs-1785, fleurs-1786, fleurs-1787, fleurs-1788, fleurs-1789, fleurs-1790, fleurs-1791, fleurs-1792, fleurs-1793, fleurs-1794, fleurs-1795, fleurs-1796, fleurs-1797, fleurs-1798, fleurs-1799, fleurs-1800, fleurs-1801, fleurs-1802, fleurs-1803, fleurs-1804, fleurs-1805, fleurs-1806, fleurs-1807, fleurs-1808, fleurs-1809, fleurs-1810, fleurs-1811, fleurs-1812, fleurs-1813, fleurs-1814, fleurs-1815, fleurs-1816, fleurs-1817, fleurs-1818, fleurs-1819, fleurs-1820, fleurs-1821, fleurs-1822, fleurs-1824, fleurs-1825, fleurs-1826, fleurs-1827, fleurs-1828, fleurs-1829, fleurs-1830, fleurs-1831, fleurs-1832, fleurs-1833, fleurs-1834, fleurs-1835, fleurs-1836, fleurs-1837, fleurs-1838, fleurs-1839, fleurs-1840, fleurs-1841, fleurs-1842, fleurs-1843, fleurs-1844, fleurs-1845, fleurs-1846, fleurs-1847, fleurs-1848, fleurs-1849, fleurs-1850, fleurs-1851, fleurs-1852, fleurs-1853, fleurs-1854, fleurs-1855, fleurs-1856, fleurs-1857, fleurs-1858, fleurs-1859, fleurs-1860, fleurs-1861, fleurs-1862, fleurs-1863, fleurs-1864, fleurs-1865, fleurs-1866, fleurs-1867, fleurs-1868, fleurs-1869, fleurs-1870, fleurs-1871, fleurs-1872, fleurs-1873, fleurs-1874, fleurs-1875, fleurs-1876, fleurs-1877, fleurs-1878, fleurs-1879, fleurs-1880, fleurs-1881, fleurs-1882, fleurs-1883, fleurs-1884, fleurs-1885, fleurs-1886, fleurs-1887, fleurs-1888, fleurs-1889, fleurs-1890, fleurs-1891, fleurs-1892, fleurs-1893, fleurs-1894, fleurs-1895, fleurs-1896, fleurs-1897, fleurs-1898, fleurs-1899, fleurs-1900, fleurs-1901, fleurs-1902, fleurs-1903, fleurs-1904, fleurs-1905, fleurs-1906, fleurs-1907, fleurs-1908, fleurs-1909, fleurs-1910, fleurs-1911, fleurs-1912, fleurs-1913, fleurs-1914, fleurs-1915, fleurs-1916, fleurs-1917, fleurs-1918, fleurs-1919, fleurs-1920, fleurs-1921, fleurs-1922, fleurs-1923, fleurs-1924, fleurs-1925, fleurs-1926, fleurs-1927, fleurs-1928, fleurs-1929, fleurs-1930, fleurs-1931, fleurs-1932, fleurs-1933, fleurs-1934, fleurs-1935, fleurs-1936, fleurs-1937, fleurs-1938, fleurs-1939, fleurs-1940, fleurs-1941, fleurs-1942, fleurs-1943, fleurs-1944, fleurs-1945, fleurs-1946, fleurs-1947, fleurs-1948, fleurs-1949, fleurs-1950, fleurs-1951, fleurs-1952, fleurs-1953, fleurs-1954, fleurs-1955, fleurs-1956, fleurs-1957, fleurs-1958, fleurs-1959, fleurs-1960, fleurs-1961, fleurs-1962, fleurs-1963, fleurs-1964, fleurs-1965, fleurs-1966, fleurs-1967, fleurs-1968, fleurs-1969, fleurs-1970, fleurs-1971, fleurs-1972, fleurs-1973, fleurs-1974, fleurs-1975, fleurs-1976, fleurs-1977, fleurs-1978, fleurs-1979, fleurs-1980, fleurs-1981, fleurs-1982, fleurs-1983, fleurs-1984, fleurs-1985, fleurs-1986, fleurs-1987, fleurs-1988, fleurs-1989, fleurs-1990, fleurs-1991, fleurs-1992, fleurs-1993, fleurs-1994, fleurs-1995, fleurs-1996, fleurs-1997, fleurs-1998, fleurs-1999, fleurs-2000, fleurs-2001, fleurs-2002, fleurs-2003, fleurs-2004, fleurs-2005, fleurs-2006, fleurs-2007, fleurs-2008, fleurs-2009.

Rates are (substitutions + deletions) / reference words of that language. Insertions have no reference word and are left out of them.

| Words | Reference words | Hits | Sub | Del | (S+D)/N |
| --- | ---: | ---: | ---: | ---: | ---: |
| tl | 9613 | 8647 | 842 | 124 | 10.05% |
| at a code switch | unavailable: no item has word-level language spans for code-switch points | | | | |
| not at a switch | unavailable: no item has word-level language spans for non-switch points | | | | |

Insertions not attributed to a language: 125. Reference words with no word-level language: 0.

### By speaker overlap

Unavailable: the reference has no overlap annotation and no timed speaker turns.

## Deletions and missing speech

Deletion bursts (at least 3 consecutive reference words deleted): 5, 30 words, 124 deletions in all.

| Item | First utterance | Words | Time | Deleted |
| --- | --- | ---: | --- | --- |
| fleurs-1682 | line-1 | 11 | untimed | may sukat ito na 29â3 4 pulgada por 24â1 2 pulgada |
| fleurs-1730 | line-1 | 4 | untimed | sa kabila ng ilog |
| fleurs-1732 | line-1 | 3 | untimed | ad 1000 1300 |
| fleurs-1855 | line-1 | 5 | untimed | leon subalit hindi ibang malalaking |
| fleurs-1888 | line-1 | 7 | untimed | mayroon itong mas kaunting yugto ng pulutgata |

Missing speech: unavailable: the reference has no timestamps.

## Performance

Four different figures. A smaller process footprint is not a smaller model: the model's Neural Engine memory is not in the footprint.

| Item | Whole-file RTF (offline) | Live commit latency | Process peak footprint | Model residency |
| --- | --- | --- | --- | --- |
| **Corpus** | 0.255 | | | |
| fleurs-1660 | 0.215 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1661 | 0.237 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1662 | 0.281 | unavailable: an offline run has no commit latency | 295 MB | 3000 MB |
| fleurs-1663 | 0.305 | unavailable: an offline run has no commit latency | 262 MB | 3000 MB |
| fleurs-1664 | 0.231 | unavailable: an offline run has no commit latency | 264 MB | 3000 MB |
| fleurs-1665 | 0.196 | unavailable: an offline run has no commit latency | 297 MB | 3000 MB |
| fleurs-1666 | 0.247 | unavailable: an offline run has no commit latency | 298 MB | 3000 MB |
| fleurs-1667 | 0.266 | unavailable: an offline run has no commit latency | 296 MB | 3000 MB |
| fleurs-1668 | 0.282 | unavailable: an offline run has no commit latency | 273 MB | 3000 MB |
| fleurs-1669 | 0.312 | unavailable: an offline run has no commit latency | 293 MB | 3000 MB |
| fleurs-1670 | 0.302 | unavailable: an offline run has no commit latency | 303 MB | 3000 MB |
| fleurs-1671 | 0.180 | unavailable: an offline run has no commit latency | 338 MB | 3000 MB |
| fleurs-1672 | 0.316 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1673 | 0.345 | unavailable: an offline run has no commit latency | 186 MB | 3000 MB |
| fleurs-1674 | 0.253 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1675 | 0.232 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1676 | 0.247 | unavailable: an offline run has no commit latency | 188 MB | 3000 MB |
| fleurs-1677 | 0.417 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1678 | 0.182 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1679 | 0.439 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1680 | 0.219 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1681 | 0.229 | unavailable: an offline run has no commit latency | 223 MB | 3000 MB |
| fleurs-1682 | 0.327 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1683 | 0.300 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1684 | 0.183 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1685 | 0.183 | unavailable: an offline run has no commit latency | 223 MB | 3000 MB |
| fleurs-1686 | 0.214 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1687 | 0.417 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1688 | 0.249 | unavailable: an offline run has no commit latency | 193 MB | 3000 MB |
| fleurs-1689 | 0.244 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1690 | 0.353 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1691 | 0.386 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1692 | 0.231 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1693 | 0.216 | unavailable: an offline run has no commit latency | 191 MB | 3000 MB |
| fleurs-1694 | 0.230 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1695 | 0.228 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1696 | 0.279 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1697 | 0.398 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1698 | 0.265 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1699 | 0.237 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1700 | 0.361 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1701 | 0.190 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1702 | 0.331 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1703 | 0.199 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1704 | 0.210 | unavailable: an offline run has no commit latency | 188 MB | 3000 MB |
| fleurs-1705 | 0.162 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1706 | 0.345 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1707 | 0.211 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1708 | 0.173 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1709 | 0.205 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1710 | 0.205 | unavailable: an offline run has no commit latency | 193 MB | 3000 MB |
| fleurs-1711 | 0.258 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1712 | 0.201 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1713 | 0.268 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1714 | 0.275 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1715 | 0.242 | unavailable: an offline run has no commit latency | 186 MB | 3000 MB |
| fleurs-1716 | 0.290 | unavailable: an offline run has no commit latency | 231 MB | 3000 MB |
| fleurs-1717 | 0.256 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1718 | 0.362 | unavailable: an offline run has no commit latency | 192 MB | 3000 MB |
| fleurs-1719 | 0.227 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1720 | 0.229 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1721 | 0.181 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1722 | 0.202 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1723 | 0.175 | unavailable: an offline run has no commit latency | 186 MB | 3000 MB |
| fleurs-1724 | 0.205 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1725 | 0.192 | unavailable: an offline run has no commit latency | 186 MB | 3000 MB |
| fleurs-1726 | 0.255 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1727 | 0.247 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1728 | 0.217 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1729 | 0.219 | unavailable: an offline run has no commit latency | 224 MB | 3000 MB |
| fleurs-1730 | 0.306 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1731 | 0.227 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1732 | 0.310 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1733 | 0.216 | unavailable: an offline run has no commit latency | 224 MB | 3000 MB |
| fleurs-1734 | 0.309 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1735 | 0.302 | unavailable: an offline run has no commit latency | 231 MB | 3000 MB |
| fleurs-1736 | 0.233 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1737 | 0.209 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1738 | 0.252 | unavailable: an offline run has no commit latency | 181 MB | 3000 MB |
| fleurs-1739 | 0.382 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1740 | 0.189 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1741 | 0.246 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1742 | 0.305 | unavailable: an offline run has no commit latency | 193 MB | 3000 MB |
| fleurs-1743 | 0.327 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1744 | 0.242 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1745 | 0.376 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1746 | 0.343 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1747 | 0.237 | unavailable: an offline run has no commit latency | 181 MB | 3000 MB |
| fleurs-1748 | 0.404 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1749 | 0.198 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1750 | 0.295 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1751 | 0.210 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1752 | 0.233 | unavailable: an offline run has no commit latency | 191 MB | 3000 MB |
| fleurs-1753 | 0.254 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1754 | 0.309 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1755 | 0.226 | unavailable: an offline run has no commit latency | 188 MB | 3000 MB |
| fleurs-1756 | 0.296 | unavailable: an offline run has no commit latency | 188 MB | 3000 MB |
| fleurs-1757 | 0.351 | unavailable: an offline run has no commit latency | 186 MB | 3000 MB |
| fleurs-1758 | 0.191 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1759 | 0.303 | unavailable: an offline run has no commit latency | 193 MB | 3000 MB |
| fleurs-1760 | 0.220 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1761 | 0.195 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1762 | 0.426 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1763 | 0.229 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1764 | 0.373 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1765 | 0.222 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1766 | 0.239 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1767 | 0.286 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1768 | 0.270 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1769 | 0.211 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1770 | 0.253 | unavailable: an offline run has no commit latency | 181 MB | 3000 MB |
| fleurs-1771 | 0.331 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1772 | 0.251 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1773 | 0.236 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1774 | 0.235 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1775 | 0.233 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1776 | 0.156 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1777 | 0.347 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1778 | 0.272 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1779 | 0.238 | unavailable: an offline run has no commit latency | 181 MB | 3000 MB |
| fleurs-1780 | 0.290 | unavailable: an offline run has no commit latency | 192 MB | 3000 MB |
| fleurs-1781 | 0.230 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1782 | 0.193 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1783 | 0.197 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1784 | 0.256 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1785 | 0.277 | unavailable: an offline run has no commit latency | 194 MB | 3000 MB |
| fleurs-1786 | 0.190 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1787 | 0.238 | unavailable: an offline run has no commit latency | 188 MB | 3000 MB |
| fleurs-1788 | 0.221 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1789 | 0.141 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1790 | 0.390 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1791 | 0.239 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1792 | 0.248 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1793 | 0.354 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1794 | 0.236 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1795 | 0.238 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1796 | 0.278 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1797 | 0.208 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1798 | 0.237 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1799 | 0.257 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1800 | 0.238 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1801 | 0.377 | unavailable: an offline run has no commit latency | 186 MB | 3000 MB |
| fleurs-1802 | 0.194 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1803 | 0.299 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1804 | 0.279 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1805 | 0.219 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1806 | 0.234 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1807 | 0.252 | unavailable: an offline run has no commit latency | 192 MB | 3000 MB |
| fleurs-1808 | 0.190 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1809 | 0.363 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1810 | 0.333 | unavailable: an offline run has no commit latency | 181 MB | 3000 MB |
| fleurs-1811 | 0.175 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1812 | 0.387 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1813 | 0.312 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1814 | 0.208 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1815 | 0.317 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1816 | 0.262 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1817 | 0.261 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1818 | 0.376 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1819 | 0.245 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1820 | 0.411 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1821 | 0.225 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1822 | 0.231 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1824 | 0.210 | unavailable: an offline run has no commit latency | 186 MB | 3000 MB |
| fleurs-1825 | 0.269 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1826 | 0.223 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1827 | 0.166 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1828 | 0.201 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1829 | 0.259 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1830 | 0.148 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1831 | 0.359 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1832 | 0.168 | unavailable: an offline run has no commit latency | 188 MB | 3000 MB |
| fleurs-1833 | 0.273 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1834 | 0.226 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1835 | 0.338 | unavailable: an offline run has no commit latency | 192 MB | 3000 MB |
| fleurs-1836 | 0.210 | unavailable: an offline run has no commit latency | 226 MB | 3000 MB |
| fleurs-1837 | 0.273 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1838 | 0.225 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1839 | 0.230 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1840 | 0.341 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1841 | 0.340 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1842 | 0.333 | unavailable: an offline run has no commit latency | 191 MB | 3000 MB |
| fleurs-1843 | 0.215 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1844 | 0.309 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1845 | 0.210 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1846 | 0.291 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1847 | 0.206 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1848 | 0.324 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1849 | 0.272 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1850 | 0.286 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1851 | 0.264 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1852 | 0.783 | unavailable: an offline run has no commit latency | 233 MB | 3000 MB |
| fleurs-1853 | 0.245 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1854 | 0.232 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1855 | 0.372 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1856 | 0.265 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1857 | 0.244 | unavailable: an offline run has no commit latency | 181 MB | 3000 MB |
| fleurs-1858 | 0.237 | unavailable: an offline run has no commit latency | 188 MB | 3000 MB |
| fleurs-1859 | 0.262 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1860 | 0.237 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1861 | 0.227 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1862 | 0.266 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1863 | 0.268 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1864 | 0.167 | unavailable: an offline run has no commit latency | 191 MB | 3000 MB |
| fleurs-1865 | 0.339 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1866 | 0.368 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1867 | 0.327 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1868 | 0.216 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1869 | 0.223 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1870 | 0.277 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1871 | 0.418 | unavailable: an offline run has no commit latency | 181 MB | 3000 MB |
| fleurs-1872 | 0.287 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1873 | 0.265 | unavailable: an offline run has no commit latency | 191 MB | 3000 MB |
| fleurs-1874 | 0.201 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1875 | 0.219 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1876 | 0.361 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1877 | 0.182 | unavailable: an offline run has no commit latency | 225 MB | 3000 MB |
| fleurs-1878 | 0.205 | unavailable: an offline run has no commit latency | 193 MB | 3000 MB |
| fleurs-1879 | 0.251 | unavailable: an offline run has no commit latency | 181 MB | 3000 MB |
| fleurs-1880 | 0.239 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1881 | 0.226 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1882 | 0.273 | unavailable: an offline run has no commit latency | 188 MB | 3000 MB |
| fleurs-1883 | 0.186 | unavailable: an offline run has no commit latency | 195 MB | 3000 MB |
| fleurs-1884 | 0.212 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1885 | 0.204 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1886 | 0.240 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1887 | 0.270 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1888 | 0.352 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1889 | 0.236 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1890 | 0.232 | unavailable: an offline run has no commit latency | 191 MB | 3000 MB |
| fleurs-1891 | 0.240 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1892 | 0.238 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1893 | 0.209 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1894 | 0.357 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1895 | 0.229 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1896 | 0.277 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1897 | 0.307 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1898 | 0.252 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1899 | 0.288 | unavailable: an offline run has no commit latency | 192 MB | 3000 MB |
| fleurs-1900 | 0.418 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1901 | 0.373 | unavailable: an offline run has no commit latency | 193 MB | 3000 MB |
| fleurs-1902 | 0.177 | unavailable: an offline run has no commit latency | 181 MB | 3000 MB |
| fleurs-1903 | 0.258 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1904 | 0.368 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1905 | 0.345 | unavailable: an offline run has no commit latency | 188 MB | 3000 MB |
| fleurs-1906 | 0.352 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1907 | 0.329 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1908 | 0.415 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1909 | 0.222 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1910 | 0.255 | unavailable: an offline run has no commit latency | 181 MB | 3000 MB |
| fleurs-1911 | 0.295 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1912 | 0.245 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1913 | 0.353 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1914 | 0.182 | unavailable: an offline run has no commit latency | 192 MB | 3000 MB |
| fleurs-1915 | 0.219 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1916 | 0.271 | unavailable: an offline run has no commit latency | 181 MB | 3000 MB |
| fleurs-1917 | 0.404 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1918 | 0.289 | unavailable: an offline run has no commit latency | 191 MB | 3000 MB |
| fleurs-1919 | 0.276 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1920 | 0.300 | unavailable: an offline run has no commit latency | 181 MB | 3000 MB |
| fleurs-1921 | 0.304 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1922 | 0.304 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1923 | 0.354 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1924 | 0.274 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1925 | 0.306 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1926 | 0.450 | unavailable: an offline run has no commit latency | 192 MB | 3000 MB |
| fleurs-1927 | 0.187 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1928 | 0.174 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1929 | 0.247 | unavailable: an offline run has no commit latency | 191 MB | 3000 MB |
| fleurs-1930 | 0.357 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1931 | 0.232 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1932 | 0.284 | unavailable: an offline run has no commit latency | 223 MB | 3000 MB |
| fleurs-1933 | 0.255 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1934 | 0.244 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1935 | 0.270 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1936 | 0.260 | unavailable: an offline run has no commit latency | 193 MB | 3000 MB |
| fleurs-1937 | 0.272 | unavailable: an offline run has no commit latency | 227 MB | 3000 MB |
| fleurs-1938 | 0.230 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1939 | 0.253 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1940 | 0.213 | unavailable: an offline run has no commit latency | 192 MB | 3000 MB |
| fleurs-1941 | 0.239 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1942 | 0.245 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1943 | 0.274 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |
| fleurs-1944 | 0.332 | unavailable: an offline run has no commit latency | 186 MB | 3000 MB |
| fleurs-1945 | 0.219 | unavailable: an offline run has no commit latency | 191 MB | 3000 MB |
| fleurs-1946 | 0.201 | unavailable: an offline run has no commit latency | 191 MB | 3000 MB |
| fleurs-1947 | 0.237 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1948 | 0.305 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1949 | 0.210 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1950 | 0.293 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1951 | 0.220 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1952 | 0.210 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1953 | 0.209 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1954 | 0.227 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1955 | 0.207 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1956 | 0.223 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1957 | 0.256 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1958 | 0.227 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1959 | 0.238 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1960 | 0.236 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1961 | 0.226 | unavailable: an offline run has no commit latency | 223 MB | 3000 MB |
| fleurs-1962 | 0.255 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1963 | 0.211 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1964 | 0.295 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1965 | 0.250 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1966 | 0.202 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1967 | 0.311 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1968 | 0.298 | unavailable: an offline run has no commit latency | 188 MB | 3000 MB |
| fleurs-1969 | 0.261 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1970 | 0.250 | unavailable: an offline run has no commit latency | 188 MB | 3000 MB |
| fleurs-1971 | 0.262 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1972 | 0.236 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1973 | 0.346 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1974 | 0.426 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1975 | 0.206 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1976 | 0.237 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1977 | 0.206 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1978 | 0.239 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1979 | 0.222 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1980 | 0.252 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1981 | 0.218 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1982 | 0.238 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1983 | 0.247 | unavailable: an offline run has no commit latency | 194 MB | 3000 MB |
| fleurs-1984 | 0.209 | unavailable: an offline run has no commit latency | 185 MB | 3000 MB |
| fleurs-1985 | 0.272 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1986 | 0.173 | unavailable: an offline run has no commit latency | 192 MB | 3000 MB |
| fleurs-1987 | 0.228 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1988 | 0.212 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1989 | 0.223 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-1990 | 0.321 | unavailable: an offline run has no commit latency | 192 MB | 3000 MB |
| fleurs-1991 | 0.213 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1992 | 0.284 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1993 | 0.215 | unavailable: an offline run has no commit latency | 190 MB | 3000 MB |
| fleurs-1994 | 0.223 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-1995 | 0.342 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1996 | 0.329 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1997 | 0.242 | unavailable: an offline run has no commit latency | 187 MB | 3000 MB |
| fleurs-1998 | 0.274 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-1999 | 0.191 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-2000 | 0.248 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-2001 | 0.220 | unavailable: an offline run has no commit latency | 184 MB | 3000 MB |
| fleurs-2002 | 0.213 | unavailable: an offline run has no commit latency | 191 MB | 3000 MB |
| fleurs-2003 | 0.254 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-2004 | 0.311 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-2005 | 0.275 | unavailable: an offline run has no commit latency | 182 MB | 3000 MB |
| fleurs-2006 | 0.222 | unavailable: an offline run has no commit latency | 183 MB | 3000 MB |
| fleurs-2007 | 0.246 | unavailable: an offline run has no commit latency | 188 MB | 3000 MB |
| fleurs-2008 | 0.211 | unavailable: an offline run has no commit latency | 194 MB | 3000 MB |
| fleurs-2009 | 0.256 | unavailable: an offline run has no commit latency | 189 MB | 3000 MB |

## Items

| Item | Category | WER | CER | N | Sub | Del | Ins |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fleurs-1660 | tagalog | 20.00% | 6.15% | 20 | 3 | 0 | 1 |
| fleurs-1661 | tagalog | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1662 | tagalog | 6.98% | 2.56% | 43 | 3 | 0 | 0 |
| fleurs-1663 | tagalog | 19.23% | 7.32% | 26 | 5 | 0 | 0 |
| fleurs-1664 | tagalog | 16.67% | 1.99% | 24 | 3 | 1 | 0 |
| fleurs-1665 | tagalog | 6.67% | 1.10% | 30 | 2 | 0 | 0 |
| fleurs-1666 | tagalog | 14.29% | 1.89% | 28 | 3 | 1 | 0 |
| fleurs-1667 | tagalog | 2.63% | 0.41% | 38 | 1 | 0 | 0 |
| fleurs-1668 | tagalog | 17.07% | 2.20% | 41 | 5 | 2 | 0 |
| fleurs-1669 | tagalog | 13.04% | 3.73% | 23 | 3 | 0 | 0 |
| fleurs-1670 | tagalog | 11.67% | 3.20% | 60 | 5 | 2 | 0 |
| fleurs-1671 | tagalog | 19.35% | 7.25% | 31 | 6 | 0 | 0 |
| fleurs-1672 | tagalog | 21.74% | 4.76% | 23 | 4 | 1 | 0 |
| fleurs-1673 | tagalog | 19.35% | 3.81% | 31 | 5 | 0 | 1 |
| fleurs-1674 | tagalog | 0.00% | 0.00% | 25 | 0 | 0 | 0 |
| fleurs-1675 | tagalog | 8.00% | 2.17% | 25 | 2 | 0 | 0 |
| fleurs-1676 | tagalog | 4.35% | 0.76% | 23 | 1 | 0 | 0 |
| fleurs-1677 | tagalog | 5.56% | 2.02% | 18 | 1 | 0 | 0 |
| fleurs-1678 | tagalog | 7.89% | 1.34% | 38 | 2 | 1 | 0 |
| fleurs-1679 | tagalog | 27.27% | 6.25% | 11 | 3 | 0 | 0 |
| fleurs-1680 | tagalog | 20.69% | 3.91% | 29 | 6 | 0 | 0 |
| fleurs-1681 | tagalog | 4.65% | 1.12% | 43 | 2 | 0 | 0 |
| fleurs-1682 | tagalog | 30.77% | 24.77% | 39 | 1 | 11 | 0 |
| fleurs-1683 | tagalog | 6.98% | 0.83% | 43 | 2 | 1 | 0 |
| fleurs-1684 | tagalog | 8.70% | 2.59% | 23 | 2 | 0 | 0 |
| fleurs-1685 | tagalog | 19.35% | 3.65% | 31 | 6 | 0 | 0 |
| fleurs-1686 | tagalog | 10.71% | 2.76% | 28 | 3 | 0 | 0 |
| fleurs-1687 | tagalog | 22.22% | 5.74% | 18 | 4 | 0 | 0 |
| fleurs-1688 | tagalog | 0.00% | 0.00% | 44 | 0 | 0 | 0 |
| fleurs-1689 | tagalog | 7.32% | 1.55% | 41 | 3 | 0 | 0 |
| fleurs-1690 | tagalog | 6.82% | 1.88% | 44 | 3 | 0 | 0 |
| fleurs-1691 | tagalog | 14.81% | 3.21% | 27 | 4 | 0 | 0 |
| fleurs-1692 | tagalog | 25.00% | 4.00% | 16 | 4 | 0 | 0 |
| fleurs-1693 | tagalog | 16.67% | 6.02% | 24 | 3 | 0 | 1 |
| fleurs-1694 | tagalog | 7.69% | 1.94% | 26 | 1 | 0 | 1 |
| fleurs-1695 | tagalog | 21.88% | 4.57% | 32 | 3 | 2 | 2 |
| fleurs-1696 | tagalog | 7.14% | 1.73% | 28 | 2 | 0 | 0 |
| fleurs-1697 | tagalog | 19.05% | 3.73% | 21 | 3 | 0 | 1 |
| fleurs-1698 | tagalog | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1699 | tagalog | 9.68% | 2.78% | 31 | 3 | 0 | 0 |
| fleurs-1700 | tagalog | 0.00% | 0.00% | 16 | 0 | 0 | 0 |
| fleurs-1701 | tagalog | 19.05% | 15.09% | 21 | 4 | 0 | 0 |
| fleurs-1702 | tagalog | 8.70% | 4.29% | 23 | 1 | 1 | 0 |
| fleurs-1703 | tagalog | 26.67% | 6.45% | 15 | 2 | 0 | 2 |
| fleurs-1704 | tagalog | 14.29% | 3.12% | 21 | 3 | 0 | 0 |
| fleurs-1705 | tagalog | 15.00% | 5.79% | 20 | 2 | 1 | 0 |
| fleurs-1706 | tagalog | 6.25% | 0.94% | 48 | 2 | 0 | 1 |
| fleurs-1707 | tagalog | 13.64% | 2.21% | 22 | 2 | 0 | 1 |
| fleurs-1708 | tagalog | 10.34% | 3.11% | 29 | 3 | 0 | 0 |
| fleurs-1709 | tagalog | 3.33% | 1.25% | 30 | 1 | 0 | 0 |
| fleurs-1710 | tagalog | 10.34% | 1.81% | 29 | 3 | 0 | 0 |
| fleurs-1711 | tagalog | 0.00% | 0.00% | 42 | 0 | 0 | 0 |
| fleurs-1712 | tagalog | 28.12% | 10.40% | 32 | 7 | 0 | 2 |
| fleurs-1713 | tagalog | 13.33% | 1.10% | 30 | 2 | 2 | 0 |
| fleurs-1714 | tagalog | 5.56% | 0.88% | 36 | 2 | 0 | 0 |
| fleurs-1715 | tagalog | 21.05% | 4.29% | 38 | 6 | 1 | 1 |
| fleurs-1716 | tagalog | 9.68% | 4.22% | 62 | 2 | 2 | 2 |
| fleurs-1717 | tagalog | 0.00% | 0.00% | 29 | 0 | 0 | 0 |
| fleurs-1718 | tagalog | 21.88% | 9.45% | 32 | 4 | 0 | 3 |
| fleurs-1719 | tagalog | 2.86% | 0.92% | 35 | 1 | 0 | 0 |
| fleurs-1720 | tagalog | 10.00% | 1.61% | 20 | 2 | 0 | 0 |
| fleurs-1721 | tagalog | 20.00% | 2.61% | 20 | 2 | 1 | 1 |
| fleurs-1722 | tagalog | 6.06% | 1.79% | 33 | 2 | 0 | 0 |
| fleurs-1723 | tagalog | 10.00% | 4.62% | 30 | 2 | 0 | 1 |
| fleurs-1724 | tagalog | 20.00% | 1.89% | 20 | 2 | 2 | 0 |
| fleurs-1725 | tagalog | 2.70% | 1.63% | 37 | 1 | 0 | 0 |
| fleurs-1726 | tagalog | 11.43% | 2.12% | 35 | 4 | 0 | 0 |
| fleurs-1727 | tagalog | 3.23% | 0.55% | 31 | 1 | 0 | 0 |
| fleurs-1728 | tagalog | 9.09% | 0.89% | 22 | 1 | 1 | 0 |
| fleurs-1729 | tagalog | 14.58% | 2.61% | 48 | 7 | 0 | 0 |
| fleurs-1730 | tagalog | 21.43% | 11.27% | 42 | 5 | 4 | 0 |
| fleurs-1731 | tagalog | 0.00% | 0.00% | 14 | 0 | 0 | 0 |
| fleurs-1732 | tagalog | 29.41% | 24.14% | 34 | 7 | 3 | 0 |
| fleurs-1733 | tagalog | 2.38% | 0.38% | 42 | 1 | 0 | 0 |
| fleurs-1734 | tagalog | 16.67% | 6.05% | 36 | 6 | 0 | 0 |
| fleurs-1735 | tagalog | 21.88% | 4.46% | 64 | 12 | 1 | 1 |
| fleurs-1736 | tagalog | 15.38% | 1.37% | 13 | 1 | 0 | 1 |
| fleurs-1737 | tagalog | 18.75% | 2.97% | 16 | 2 | 0 | 1 |
| fleurs-1738 | tagalog | 14.29% | 2.56% | 21 | 3 | 0 | 0 |
| fleurs-1739 | tagalog | 4.35% | 0.84% | 23 | 1 | 0 | 0 |
| fleurs-1740 | tagalog | 9.52% | 0.94% | 21 | 1 | 1 | 0 |
| fleurs-1741 | tagalog | 10.53% | 0.97% | 19 | 1 | 1 | 0 |
| fleurs-1742 | tagalog | 14.81% | 1.20% | 27 | 2 | 2 | 0 |
| fleurs-1743 | tagalog | 7.84% | 1.45% | 51 | 4 | 0 | 0 |
| fleurs-1744 | tagalog | 11.76% | 1.87% | 17 | 1 | 0 | 1 |
| fleurs-1745 | tagalog | 8.70% | 2.14% | 23 | 2 | 0 | 0 |
| fleurs-1746 | tagalog | 10.53% | 1.74% | 19 | 2 | 0 | 0 |
| fleurs-1747 | tagalog | 11.11% | 1.79% | 9 | 1 | 0 | 0 |
| fleurs-1748 | tagalog | 35.71% | 4.23% | 14 | 2 | 1 | 2 |
| fleurs-1749 | tagalog | 5.88% | 2.73% | 34 | 1 | 1 | 0 |
| fleurs-1750 | tagalog | 6.67% | 1.22% | 15 | 1 | 0 | 0 |
| fleurs-1751 | tagalog | 13.51% | 1.42% | 37 | 3 | 2 | 0 |
| fleurs-1752 | tagalog | 4.55% | 2.34% | 22 | 0 | 0 | 1 |
| fleurs-1753 | tagalog | 5.13% | 0.77% | 39 | 2 | 0 | 0 |
| fleurs-1754 | tagalog | 18.52% | 5.23% | 27 | 4 | 0 | 1 |
| fleurs-1755 | tagalog | 18.18% | 3.08% | 11 | 2 | 0 | 0 |
| fleurs-1756 | tagalog | 8.57% | 2.12% | 35 | 3 | 0 | 0 |
| fleurs-1757 | tagalog | 6.45% | 0.56% | 31 | 1 | 0 | 1 |
| fleurs-1758 | tagalog | 0.00% | 0.00% | 22 | 0 | 0 | 0 |
| fleurs-1759 | tagalog | 14.58% | 4.35% | 48 | 6 | 1 | 0 |
| fleurs-1760 | tagalog | 0.00% | 0.00% | 17 | 0 | 0 | 0 |
| fleurs-1761 | tagalog | 0.00% | 0.00% | 21 | 0 | 0 | 0 |
| fleurs-1762 | tagalog | 5.88% | 2.44% | 17 | 1 | 0 | 0 |
| fleurs-1763 | tagalog | 6.45% | 1.12% | 31 | 1 | 0 | 1 |
| fleurs-1764 | tagalog | 17.65% | 3.64% | 17 | 2 | 0 | 1 |
| fleurs-1765 | tagalog | 11.11% | 4.38% | 18 | 2 | 0 | 0 |
| fleurs-1766 | tagalog | 0.00% | 0.00% | 35 | 0 | 0 | 0 |
| fleurs-1767 | tagalog | 16.00% | 11.31% | 25 | 3 | 1 | 0 |
| fleurs-1768 | tagalog | 3.33% | 1.84% | 30 | 1 | 0 | 0 |
| fleurs-1769 | tagalog | 8.33% | 3.12% | 24 | 2 | 0 | 0 |
| fleurs-1770 | tagalog | 0.00% | 0.00% | 14 | 0 | 0 | 0 |
| fleurs-1771 | tagalog | 3.33% | 0.57% | 30 | 1 | 0 | 0 |
| fleurs-1772 | tagalog | 16.67% | 2.60% | 12 | 1 | 1 | 0 |
| fleurs-1773 | tagalog | 11.11% | 6.36% | 27 | 2 | 0 | 1 |
| fleurs-1774 | tagalog | 4.76% | 1.29% | 42 | 2 | 0 | 0 |
| fleurs-1775 | tagalog | 9.38% | 2.45% | 32 | 3 | 0 | 0 |
| fleurs-1776 | tagalog | 0.00% | 0.00% | 23 | 0 | 0 | 0 |
| fleurs-1777 | tagalog | 6.67% | 1.75% | 30 | 2 | 0 | 0 |
| fleurs-1778 | tagalog | 7.69% | 1.35% | 13 | 1 | 0 | 0 |
| fleurs-1779 | tagalog | 5.26% | 1.79% | 19 | 1 | 0 | 0 |
| fleurs-1780 | tagalog | 16.00% | 3.77% | 25 | 3 | 0 | 1 |
| fleurs-1781 | tagalog | 13.33% | 3.03% | 15 | 1 | 0 | 1 |
| fleurs-1782 | tagalog | 2.50% | 0.47% | 40 | 1 | 0 | 0 |
| fleurs-1783 | tagalog | 22.73% | 3.85% | 22 | 4 | 1 | 0 |
| fleurs-1784 | tagalog | 9.09% | 1.43% | 44 | 3 | 1 | 0 |
| fleurs-1785 | tagalog | 3.70% | 1.24% | 54 | 2 | 0 | 0 |
| fleurs-1786 | tagalog | 7.41% | 1.26% | 27 | 1 | 0 | 1 |
| fleurs-1787 | tagalog | 6.45% | 2.19% | 31 | 2 | 0 | 0 |
| fleurs-1788 | tagalog | 5.26% | 0.43% | 38 | 1 | 1 | 0 |
| fleurs-1789 | tagalog | 0.00% | 0.00% | 25 | 0 | 0 | 0 |
| fleurs-1790 | tagalog | 24.32% | 8.52% | 37 | 7 | 1 | 1 |
| fleurs-1791 | tagalog | 0.00% | 0.00% | 14 | 0 | 0 | 0 |
| fleurs-1792 | tagalog | 5.56% | 1.01% | 18 | 1 | 0 | 0 |
| fleurs-1793 | tagalog | 14.29% | 4.10% | 21 | 3 | 0 | 0 |
| fleurs-1794 | tagalog | 5.26% | 1.53% | 19 | 1 | 0 | 0 |
| fleurs-1795 | tagalog | 8.51% | 1.15% | 47 | 3 | 1 | 0 |
| fleurs-1796 | tagalog | 0.00% | 0.00% | 21 | 0 | 0 | 0 |
| fleurs-1797 | tagalog | 0.00% | 0.00% | 22 | 0 | 0 | 0 |
| fleurs-1798 | tagalog | 10.00% | 2.92% | 30 | 3 | 0 | 0 |
| fleurs-1799 | tagalog | 12.50% | 3.54% | 16 | 2 | 0 | 0 |
| fleurs-1800 | tagalog | 4.35% | 0.66% | 23 | 1 | 0 | 0 |
| fleurs-1801 | tagalog | 5.88% | 1.51% | 34 | 1 | 0 | 1 |
| fleurs-1802 | tagalog | 0.00% | 0.00% | 12 | 0 | 0 | 0 |
| fleurs-1803 | tagalog | 11.54% | 1.94% | 26 | 3 | 0 | 0 |
| fleurs-1804 | tagalog | 16.28% | 4.21% | 43 | 5 | 0 | 2 |
| fleurs-1805 | tagalog | 14.29% | 4.71% | 14 | 2 | 0 | 0 |
| fleurs-1806 | tagalog | 7.14% | 1.35% | 42 | 3 | 0 | 0 |
| fleurs-1807 | tagalog | 7.14% | 1.70% | 28 | 2 | 0 | 0 |
| fleurs-1808 | tagalog | 4.76% | 1.55% | 21 | 1 | 0 | 0 |
| fleurs-1809 | tagalog | 17.65% | 3.86% | 34 | 5 | 0 | 1 |
| fleurs-1810 | tagalog | 8.57% | 0.93% | 35 | 2 | 0 | 1 |
| fleurs-1811 | tagalog | 10.00% | 1.16% | 20 | 1 | 1 | 0 |
| fleurs-1812 | tagalog | 25.71% | 10.55% | 35 | 6 | 1 | 2 |
| fleurs-1813 | tagalog | 20.00% | 7.14% | 30 | 6 | 0 | 0 |
| fleurs-1814 | tagalog | 3.57% | 0.65% | 28 | 1 | 0 | 0 |
| fleurs-1815 | tagalog | 4.76% | 0.75% | 21 | 1 | 0 | 0 |
| fleurs-1816 | tagalog | 20.69% | 2.60% | 29 | 4 | 2 | 0 |
| fleurs-1817 | tagalog | 18.75% | 4.30% | 16 | 3 | 0 | 0 |
| fleurs-1818 | tagalog | 23.81% | 5.17% | 21 | 4 | 1 | 0 |
| fleurs-1819 | tagalog | 3.70% | 0.56% | 27 | 1 | 0 | 0 |
| fleurs-1820 | tagalog | 18.18% | 6.15% | 22 | 4 | 0 | 0 |
| fleurs-1821 | tagalog | 5.26% | 0.83% | 19 | 1 | 0 | 0 |
| fleurs-1822 | tagalog | 28.12% | 5.15% | 32 | 7 | 1 | 1 |
| fleurs-1824 | tagalog | 5.41% | 1.38% | 37 | 2 | 0 | 0 |
| fleurs-1825 | tagalog | 5.88% | 3.74% | 17 | 0 | 0 | 1 |
| fleurs-1826 | tagalog | 26.67% | 3.03% | 15 | 3 | 0 | 1 |
| fleurs-1827 | tagalog | 8.70% | 12.73% | 23 | 2 | 0 | 0 |
| fleurs-1828 | tagalog | 13.04% | 2.16% | 23 | 3 | 0 | 0 |
| fleurs-1829 | tagalog | 0.00% | 0.00% | 35 | 0 | 0 | 0 |
| fleurs-1830 | tagalog | 17.65% | 7.14% | 17 | 2 | 1 | 0 |
| fleurs-1831 | tagalog | 6.67% | 1.69% | 30 | 2 | 0 | 0 |
| fleurs-1832 | tagalog | 15.38% | 9.49% | 26 | 4 | 0 | 0 |
| fleurs-1833 | tagalog | 6.25% | 1.81% | 32 | 2 | 0 | 0 |
| fleurs-1834 | tagalog | 3.70% | 0.66% | 27 | 1 | 0 | 0 |
| fleurs-1835 | tagalog | 12.50% | 2.76% | 32 | 4 | 0 | 0 |
| fleurs-1836 | tagalog | 11.11% | 4.44% | 45 | 3 | 2 | 0 |
| fleurs-1837 | tagalog | 11.54% | 1.20% | 26 | 2 | 0 | 1 |
| fleurs-1838 | tagalog | 22.22% | 6.73% | 18 | 2 | 2 | 0 |
| fleurs-1839 | tagalog | 15.38% | 1.47% | 13 | 1 | 1 | 0 |
| fleurs-1840 | tagalog | 12.50% | 2.94% | 32 | 4 | 0 | 0 |
| fleurs-1841 | tagalog | 0.00% | 0.00% | 27 | 0 | 0 | 0 |
| fleurs-1842 | tagalog | 10.42% | 3.25% | 48 | 4 | 0 | 1 |
| fleurs-1843 | tagalog | 23.33% | 8.11% | 30 | 5 | 0 | 2 |
| fleurs-1844 | tagalog | 14.29% | 2.88% | 21 | 3 | 0 | 0 |
| fleurs-1845 | tagalog | 19.23% | 7.45% | 26 | 4 | 1 | 0 |
| fleurs-1846 | tagalog | 20.83% | 13.74% | 24 | 4 | 0 | 1 |
| fleurs-1847 | tagalog | 3.33% | 0.61% | 30 | 1 | 0 | 0 |
| fleurs-1848 | tagalog | 20.59% | 4.57% | 34 | 5 | 1 | 1 |
| fleurs-1849 | tagalog | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1850 | tagalog | 12.00% | 4.35% | 25 | 3 | 0 | 0 |
| fleurs-1851 | tagalog | 7.14% | 0.65% | 28 | 1 | 0 | 1 |
| fleurs-1852 | tagalog | 36.51% | 15.92% | 63 | 13 | 1 | 9 |
| fleurs-1853 | tagalog | 5.00% | 4.27% | 20 | 1 | 0 | 0 |
| fleurs-1854 | tagalog | 15.79% | 2.80% | 19 | 2 | 0 | 1 |
| fleurs-1855 | tagalog | 41.03% | 23.11% | 39 | 7 | 7 | 2 |
| fleurs-1856 | tagalog | 0.00% | 0.00% | 31 | 0 | 0 | 0 |
| fleurs-1857 | tagalog | 14.81% | 1.89% | 27 | 2 | 1 | 1 |
| fleurs-1858 | tagalog | 8.70% | 2.13% | 23 | 2 | 0 | 0 |
| fleurs-1859 | tagalog | 14.63% | 2.36% | 41 | 5 | 0 | 1 |
| fleurs-1860 | tagalog | 12.50% | 2.27% | 16 | 1 | 1 | 0 |
| fleurs-1861 | tagalog | 27.27% | 4.48% | 22 | 4 | 0 | 2 |
| fleurs-1862 | tagalog | 5.41% | 1.40% | 37 | 2 | 0 | 0 |
| fleurs-1863 | tagalog | 9.52% | 4.55% | 42 | 2 | 2 | 0 |
| fleurs-1864 | tagalog | 10.81% | 2.88% | 37 | 4 | 0 | 0 |
| fleurs-1865 | tagalog | 15.62% | 5.67% | 32 | 4 | 1 | 0 |
| fleurs-1866 | tagalog | 5.00% | 0.81% | 20 | 1 | 0 | 0 |
| fleurs-1867 | tagalog | 10.71% | 3.11% | 28 | 3 | 0 | 0 |
| fleurs-1868 | tagalog | 6.90% | 1.68% | 29 | 2 | 0 | 0 |
| fleurs-1869 | tagalog | 15.62% | 6.25% | 32 | 4 | 0 | 1 |
| fleurs-1870 | tagalog | 17.65% | 6.32% | 17 | 2 | 1 | 0 |
| fleurs-1871 | tagalog | 7.69% | 2.56% | 13 | 1 | 0 | 0 |
| fleurs-1872 | tagalog | 25.81% | 5.61% | 31 | 6 | 1 | 1 |
| fleurs-1873 | tagalog | 0.00% | 0.00% | 26 | 0 | 0 | 0 |
| fleurs-1874 | tagalog | 9.68% | 2.89% | 31 | 3 | 0 | 0 |
| fleurs-1875 | tagalog | 4.55% | 9.82% | 22 | 0 | 1 | 0 |
| fleurs-1876 | tagalog | 11.11% | 1.74% | 18 | 2 | 0 | 0 |
| fleurs-1877 | tagalog | 10.81% | 3.51% | 37 | 3 | 0 | 1 |
| fleurs-1878 | tagalog | 11.11% | 3.23% | 36 | 4 | 0 | 0 |
| fleurs-1879 | tagalog | 0.00% | 0.00% | 18 | 0 | 0 | 0 |
| fleurs-1880 | tagalog | 14.29% | 2.35% | 14 | 1 | 0 | 1 |
| fleurs-1881 | tagalog | 7.14% | 2.21% | 28 | 2 | 0 | 0 |
| fleurs-1882 | tagalog | 15.62% | 4.79% | 32 | 4 | 1 | 0 |
| fleurs-1883 | tagalog | 8.00% | 5.71% | 25 | 0 | 0 | 2 |
| fleurs-1884 | tagalog | 9.09% | 1.95% | 22 | 2 | 0 | 0 |
| fleurs-1885 | tagalog | 45.00% | 46.32% | 20 | 5 | 0 | 4 |
| fleurs-1886 | tagalog | 0.00% | 0.00% | 23 | 0 | 0 | 0 |
| fleurs-1887 | tagalog | 11.11% | 1.49% | 18 | 2 | 0 | 0 |
| fleurs-1888 | tagalog | 31.03% | 26.23% | 29 | 2 | 7 | 0 |
| fleurs-1889 | tagalog | 0.00% | 0.00% | 16 | 0 | 0 | 0 |
| fleurs-1890 | tagalog | 10.00% | 1.36% | 20 | 2 | 0 | 0 |
| fleurs-1891 | tagalog | 56.25% | 12.15% | 16 | 7 | 0 | 2 |
| fleurs-1892 | tagalog | 0.00% | 0.00% | 33 | 0 | 0 | 0 |
| fleurs-1893 | tagalog | 9.38% | 3.31% | 32 | 3 | 0 | 0 |
| fleurs-1894 | tagalog | 0.00% | 0.00% | 19 | 0 | 0 | 0 |
| fleurs-1895 | tagalog | 18.18% | 4.17% | 22 | 4 | 0 | 0 |
| fleurs-1896 | tagalog | 19.05% | 3.91% | 42 | 7 | 1 | 0 |
| fleurs-1897 | tagalog | 17.65% | 6.19% | 17 | 2 | 1 | 0 |
| fleurs-1898 | tagalog | 2.94% | 1.94% | 34 | 1 | 0 | 0 |
| fleurs-1899 | tagalog | 10.26% | 1.35% | 39 | 3 | 1 | 0 |
| fleurs-1900 | tagalog | 4.35% | 2.19% | 23 | 0 | 1 | 0 |
| fleurs-1901 | tagalog | 13.51% | 3.65% | 37 | 4 | 0 | 1 |
| fleurs-1902 | tagalog | 33.33% | 7.46% | 12 | 3 | 0 | 1 |
| fleurs-1903 | tagalog | 4.76% | 0.67% | 21 | 1 | 0 | 0 |
| fleurs-1904 | tagalog | 8.70% | 1.47% | 23 | 2 | 0 | 0 |
| fleurs-1905 | tagalog | 22.22% | 7.96% | 18 | 4 | 0 | 0 |
| fleurs-1906 | tagalog | 14.29% | 8.24% | 14 | 1 | 0 | 1 |
| fleurs-1907 | tagalog | 35.29% | 5.36% | 17 | 5 | 1 | 0 |
| fleurs-1908 | tagalog | 6.67% | 2.20% | 15 | 1 | 0 | 0 |
| fleurs-1909 | tagalog | 7.69% | 1.80% | 26 | 2 | 0 | 0 |
| fleurs-1910 | tagalog | 9.09% | 1.56% | 11 | 1 | 0 | 0 |
| fleurs-1911 | tagalog | 13.33% | 2.13% | 30 | 3 | 0 | 1 |
| fleurs-1912 | tagalog | 0.00% | 0.00% | 20 | 0 | 0 | 0 |
| fleurs-1913 | tagalog | 3.85% | 2.70% | 26 | 1 | 0 | 0 |
| fleurs-1914 | tagalog | 29.41% | 3.36% | 17 | 3 | 1 | 1 |
| fleurs-1915 | tagalog | 11.54% | 8.92% | 26 | 3 | 0 | 0 |
| fleurs-1916 | tagalog | 12.50% | 6.47% | 32 | 2 | 1 | 1 |
| fleurs-1917 | tagalog | 20.00% | 8.40% | 20 | 3 | 0 | 1 |
| fleurs-1918 | tagalog | 20.00% | 2.37% | 25 | 4 | 0 | 1 |
| fleurs-1919 | tagalog | 16.00% | 2.04% | 25 | 3 | 1 | 0 |
| fleurs-1920 | tagalog | 4.00% | 1.29% | 25 | 1 | 0 | 0 |
| fleurs-1921 | tagalog | 8.70% | 1.49% | 23 | 2 | 0 | 0 |
| fleurs-1922 | tagalog | 30.77% | 8.14% | 26 | 8 | 0 | 0 |
| fleurs-1923 | tagalog | 19.57% | 4.10% | 46 | 9 | 0 | 0 |
| fleurs-1924 | tagalog | 48.15% | 32.47% | 27 | 8 | 0 | 5 |
| fleurs-1925 | tagalog | 23.81% | 3.97% | 21 | 4 | 0 | 1 |
| fleurs-1926 | tagalog | 18.75% | 4.85% | 16 | 3 | 0 | 0 |
| fleurs-1927 | tagalog | 4.17% | 0.64% | 24 | 1 | 0 | 0 |
| fleurs-1928 | tagalog | 29.41% | 21.01% | 17 | 4 | 1 | 0 |
| fleurs-1929 | tagalog | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1930 | tagalog | 11.11% | 1.80% | 18 | 2 | 0 | 0 |
| fleurs-1931 | tagalog | 0.00% | 0.00% | 36 | 0 | 0 | 0 |
| fleurs-1932 | tagalog | 10.53% | 2.87% | 57 | 5 | 1 | 0 |
| fleurs-1933 | tagalog | 0.00% | 0.00% | 32 | 0 | 0 | 0 |
| fleurs-1934 | tagalog | 7.41% | 1.32% | 27 | 2 | 0 | 0 |
| fleurs-1935 | tagalog | 18.75% | 2.94% | 16 | 2 | 1 | 0 |
| fleurs-1936 | tagalog | 6.00% | 2.55% | 50 | 2 | 0 | 1 |
| fleurs-1937 | tagalog | 11.59% | 4.20% | 69 | 7 | 1 | 0 |
| fleurs-1938 | tagalog | 8.33% | 3.27% | 24 | 1 | 0 | 1 |
| fleurs-1939 | tagalog | 19.23% | 1.71% | 26 | 3 | 1 | 1 |
| fleurs-1940 | tagalog | 12.12% | 1.95% | 33 | 4 | 0 | 0 |
| fleurs-1941 | tagalog | 9.09% | 5.88% | 11 | 0 | 0 | 1 |
| fleurs-1942 | tagalog | 10.81% | 2.42% | 37 | 3 | 0 | 1 |
| fleurs-1943 | tagalog | 10.71% | 1.76% | 28 | 3 | 0 | 0 |
| fleurs-1944 | tagalog | 0.00% | 0.00% | 28 | 0 | 0 | 0 |
| fleurs-1945 | tagalog | 11.76% | 1.05% | 17 | 1 | 0 | 1 |
| fleurs-1946 | tagalog | 8.33% | 4.37% | 36 | 1 | 1 | 1 |
| fleurs-1947 | tagalog | 4.35% | 0.78% | 23 | 1 | 0 | 0 |
| fleurs-1948 | tagalog | 18.18% | 7.04% | 33 | 4 | 1 | 1 |
| fleurs-1949 | tagalog | 16.67% | 4.00% | 18 | 3 | 0 | 0 |
| fleurs-1950 | tagalog | 5.88% | 2.86% | 34 | 2 | 0 | 0 |
| fleurs-1951 | tagalog | 3.57% | 1.32% | 28 | 1 | 0 | 0 |
| fleurs-1952 | tagalog | 19.35% | 3.28% | 31 | 5 | 0 | 1 |
| fleurs-1953 | tagalog | 0.00% | 0.00% | 11 | 0 | 0 | 0 |
| fleurs-1954 | tagalog | 10.34% | 1.53% | 29 | 3 | 0 | 0 |
| fleurs-1955 | tagalog | 4.76% | 0.91% | 21 | 1 | 0 | 0 |
| fleurs-1956 | tagalog | 0.00% | 0.00% | 33 | 0 | 0 | 0 |
| fleurs-1957 | tagalog | 16.67% | 1.32% | 12 | 1 | 1 | 0 |
| fleurs-1958 | tagalog | 4.35% | 0.86% | 23 | 1 | 0 | 0 |
| fleurs-1959 | tagalog | 10.53% | 3.23% | 19 | 2 | 0 | 0 |
| fleurs-1960 | tagalog | 7.32% | 1.74% | 41 | 3 | 0 | 0 |
| fleurs-1961 | tagalog | 6.82% | 0.66% | 44 | 2 | 0 | 1 |
| fleurs-1962 | tagalog | 10.53% | 6.45% | 19 | 2 | 0 | 0 |
| fleurs-1963 | tagalog | 24.24% | 3.12% | 33 | 6 | 2 | 0 |
| fleurs-1964 | tagalog | 7.41% | 3.01% | 27 | 1 | 0 | 1 |
| fleurs-1965 | tagalog | 3.85% | 0.66% | 26 | 1 | 0 | 0 |
| fleurs-1966 | tagalog | 5.56% | 0.88% | 18 | 1 | 0 | 0 |
| fleurs-1967 | tagalog | 11.43% | 6.17% | 35 | 3 | 0 | 1 |
| fleurs-1968 | tagalog | 2.38% | 0.43% | 42 | 1 | 0 | 0 |
| fleurs-1969 | tagalog | 6.67% | 1.67% | 30 | 2 | 0 | 0 |
| fleurs-1970 | tagalog | 16.13% | 2.66% | 31 | 4 | 1 | 0 |
| fleurs-1971 | tagalog | 13.33% | 1.78% | 45 | 4 | 2 | 0 |
| fleurs-1972 | tagalog | 0.00% | 0.00% | 18 | 0 | 0 | 0 |
| fleurs-1973 | tagalog | 9.38% | 5.10% | 32 | 2 | 1 | 0 |
| fleurs-1974 | tagalog | 23.08% | 2.17% | 13 | 2 | 0 | 1 |
| fleurs-1975 | tagalog | 4.35% | 0.70% | 23 | 1 | 0 | 0 |
| fleurs-1976 | tagalog | 16.67% | 4.93% | 24 | 4 | 0 | 0 |
| fleurs-1977 | tagalog | 13.64% | 4.55% | 22 | 2 | 0 | 1 |
| fleurs-1978 | tagalog | 16.67% | 1.41% | 12 | 1 | 0 | 1 |
| fleurs-1979 | tagalog | 23.81% | 9.91% | 21 | 3 | 0 | 2 |
| fleurs-1980 | tagalog | 20.00% | 12.97% | 25 | 4 | 1 | 0 |
| fleurs-1981 | tagalog | 13.64% | 6.82% | 22 | 2 | 0 | 1 |
| fleurs-1982 | tagalog | 22.73% | 3.52% | 22 | 3 | 1 | 1 |
| fleurs-1983 | tagalog | 7.50% | 0.77% | 40 | 2 | 0 | 1 |
| fleurs-1984 | tagalog | 7.89% | 0.91% | 38 | 2 | 1 | 0 |
| fleurs-1985 | tagalog | 4.88% | 0.84% | 41 | 2 | 0 | 0 |
| fleurs-1986 | tagalog | 27.27% | 9.02% | 22 | 4 | 0 | 2 |
| fleurs-1987 | tagalog | 11.76% | 0.92% | 17 | 1 | 0 | 1 |
| fleurs-1988 | tagalog | 0.00% | 0.00% | 22 | 0 | 0 | 0 |
| fleurs-1989 | tagalog | 23.68% | 17.17% | 38 | 6 | 1 | 2 |
| fleurs-1990 | tagalog | 2.22% | 0.36% | 45 | 1 | 0 | 0 |
| fleurs-1991 | tagalog | 0.00% | 0.00% | 19 | 0 | 0 | 0 |
| fleurs-1992 | tagalog | 19.23% | 3.18% | 26 | 4 | 0 | 1 |
| fleurs-1993 | tagalog | 19.05% | 2.74% | 21 | 3 | 0 | 1 |
| fleurs-1994 | tagalog | 9.09% | 1.64% | 22 | 2 | 0 | 0 |
| fleurs-1995 | tagalog | 23.53% | 4.72% | 34 | 6 | 1 | 1 |
| fleurs-1996 | tagalog | 15.62% | 3.45% | 32 | 5 | 0 | 0 |
| fleurs-1997 | tagalog | 27.78% | 5.42% | 36 | 9 | 0 | 1 |
| fleurs-1998 | tagalog | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1999 | tagalog | 4.00% | 0.66% | 25 | 1 | 0 | 0 |
| fleurs-2000 | tagalog | 3.33% | 0.53% | 30 | 1 | 0 | 0 |
| fleurs-2001 | tagalog | 0.00% | 0.00% | 34 | 0 | 0 | 0 |
| fleurs-2002 | tagalog | 4.17% | 1.47% | 24 | 1 | 0 | 0 |
| fleurs-2003 | tagalog | 0.00% | 0.00% | 20 | 0 | 0 | 0 |
| fleurs-2004 | tagalog | 12.00% | 2.80% | 25 | 3 | 0 | 0 |
| fleurs-2005 | tagalog | 6.67% | 3.23% | 15 | 0 | 1 | 0 |
| fleurs-2006 | tagalog | 4.35% | 0.78% | 23 | 1 | 0 | 0 |
| fleurs-2007 | tagalog | 18.52% | 4.20% | 27 | 4 | 1 | 0 |
| fleurs-2008 | tagalog | 2.33% | 0.39% | 43 | 1 | 0 | 0 |
| fleurs-2009 | tagalog | 4.55% | 0.84% | 44 | 2 | 0 | 0 |

## Utterances

| Item | Utterance | Language | Speaker | Overlap | Time | WER | CER | N | Sub | Del | Ins |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fleurs-1660 | line-1 | tagalog |  |  |  | 20.00% | 6.15% | 20 | 3 | 0 | 1 |
| fleurs-1661 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1662 | line-1 | tagalog |  |  |  | 6.98% | 2.56% | 43 | 3 | 0 | 0 |
| fleurs-1663 | line-1 | tagalog |  |  |  | 19.23% | 7.32% | 26 | 5 | 0 | 0 |
| fleurs-1664 | line-1 | tagalog |  |  |  | 16.67% | 1.99% | 24 | 3 | 1 | 0 |
| fleurs-1665 | line-1 | tagalog |  |  |  | 6.67% | 1.10% | 30 | 2 | 0 | 0 |
| fleurs-1666 | line-1 | tagalog |  |  |  | 14.29% | 1.89% | 28 | 3 | 1 | 0 |
| fleurs-1667 | line-1 | tagalog |  |  |  | 2.63% | 0.41% | 38 | 1 | 0 | 0 |
| fleurs-1668 | line-1 | tagalog |  |  |  | 17.07% | 2.20% | 41 | 5 | 2 | 0 |
| fleurs-1669 | line-1 | tagalog |  |  |  | 13.04% | 3.73% | 23 | 3 | 0 | 0 |
| fleurs-1670 | line-1 | tagalog |  |  |  | 11.67% | 3.20% | 60 | 5 | 2 | 0 |
| fleurs-1671 | line-1 | tagalog |  |  |  | 19.35% | 7.25% | 31 | 6 | 0 | 0 |
| fleurs-1672 | line-1 | tagalog |  |  |  | 21.74% | 4.76% | 23 | 4 | 1 | 0 |
| fleurs-1673 | line-1 | tagalog |  |  |  | 19.35% | 3.81% | 31 | 5 | 0 | 1 |
| fleurs-1674 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 25 | 0 | 0 | 0 |
| fleurs-1675 | line-1 | tagalog |  |  |  | 8.00% | 2.17% | 25 | 2 | 0 | 0 |
| fleurs-1676 | line-1 | tagalog |  |  |  | 4.35% | 0.76% | 23 | 1 | 0 | 0 |
| fleurs-1677 | line-1 | tagalog |  |  |  | 5.56% | 2.02% | 18 | 1 | 0 | 0 |
| fleurs-1678 | line-1 | tagalog |  |  |  | 7.89% | 1.34% | 38 | 2 | 1 | 0 |
| fleurs-1679 | line-1 | tagalog |  |  |  | 27.27% | 6.25% | 11 | 3 | 0 | 0 |
| fleurs-1680 | line-1 | tagalog |  |  |  | 20.69% | 3.91% | 29 | 6 | 0 | 0 |
| fleurs-1681 | line-1 | tagalog |  |  |  | 4.65% | 1.12% | 43 | 2 | 0 | 0 |
| fleurs-1682 | line-1 | tagalog |  |  |  | 30.77% | 24.77% | 39 | 1 | 11 | 0 |
| fleurs-1683 | line-1 | tagalog |  |  |  | 6.98% | 0.83% | 43 | 2 | 1 | 0 |
| fleurs-1684 | line-1 | tagalog |  |  |  | 8.70% | 2.59% | 23 | 2 | 0 | 0 |
| fleurs-1685 | line-1 | tagalog |  |  |  | 19.35% | 3.65% | 31 | 6 | 0 | 0 |
| fleurs-1686 | line-1 | tagalog |  |  |  | 10.71% | 2.76% | 28 | 3 | 0 | 0 |
| fleurs-1687 | line-1 | tagalog |  |  |  | 22.22% | 5.74% | 18 | 4 | 0 | 0 |
| fleurs-1688 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 44 | 0 | 0 | 0 |
| fleurs-1689 | line-1 | tagalog |  |  |  | 7.32% | 1.55% | 41 | 3 | 0 | 0 |
| fleurs-1690 | line-1 | tagalog |  |  |  | 6.82% | 1.88% | 44 | 3 | 0 | 0 |
| fleurs-1691 | line-1 | tagalog |  |  |  | 14.81% | 3.21% | 27 | 4 | 0 | 0 |
| fleurs-1692 | line-1 | tagalog |  |  |  | 25.00% | 4.00% | 16 | 4 | 0 | 0 |
| fleurs-1693 | line-1 | tagalog |  |  |  | 16.67% | 6.02% | 24 | 3 | 0 | 1 |
| fleurs-1694 | line-1 | tagalog |  |  |  | 7.69% | 1.94% | 26 | 1 | 0 | 1 |
| fleurs-1695 | line-1 | tagalog |  |  |  | 21.88% | 4.57% | 32 | 3 | 2 | 2 |
| fleurs-1696 | line-1 | tagalog |  |  |  | 7.14% | 1.73% | 28 | 2 | 0 | 0 |
| fleurs-1697 | line-1 | tagalog |  |  |  | 19.05% | 3.73% | 21 | 3 | 0 | 1 |
| fleurs-1698 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1699 | line-1 | tagalog |  |  |  | 9.68% | 2.78% | 31 | 3 | 0 | 0 |
| fleurs-1700 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 16 | 0 | 0 | 0 |
| fleurs-1701 | line-1 | tagalog |  |  |  | 19.05% | 15.09% | 21 | 4 | 0 | 0 |
| fleurs-1702 | line-1 | tagalog |  |  |  | 8.70% | 4.29% | 23 | 1 | 1 | 0 |
| fleurs-1703 | line-1 | tagalog |  |  |  | 26.67% | 6.45% | 15 | 2 | 0 | 2 |
| fleurs-1704 | line-1 | tagalog |  |  |  | 14.29% | 3.12% | 21 | 3 | 0 | 0 |
| fleurs-1705 | line-1 | tagalog |  |  |  | 15.00% | 5.79% | 20 | 2 | 1 | 0 |
| fleurs-1706 | line-1 | tagalog |  |  |  | 6.25% | 0.94% | 48 | 2 | 0 | 1 |
| fleurs-1707 | line-1 | tagalog |  |  |  | 13.64% | 2.21% | 22 | 2 | 0 | 1 |
| fleurs-1708 | line-1 | tagalog |  |  |  | 10.34% | 3.11% | 29 | 3 | 0 | 0 |
| fleurs-1709 | line-1 | tagalog |  |  |  | 3.33% | 1.25% | 30 | 1 | 0 | 0 |
| fleurs-1710 | line-1 | tagalog |  |  |  | 10.34% | 1.81% | 29 | 3 | 0 | 0 |
| fleurs-1711 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 42 | 0 | 0 | 0 |
| fleurs-1712 | line-1 | tagalog |  |  |  | 28.12% | 10.40% | 32 | 7 | 0 | 2 |
| fleurs-1713 | line-1 | tagalog |  |  |  | 13.33% | 1.10% | 30 | 2 | 2 | 0 |
| fleurs-1714 | line-1 | tagalog |  |  |  | 5.56% | 0.88% | 36 | 2 | 0 | 0 |
| fleurs-1715 | line-1 | tagalog |  |  |  | 21.05% | 4.29% | 38 | 6 | 1 | 1 |
| fleurs-1716 | line-1 | tagalog |  |  |  | 9.68% | 4.22% | 62 | 2 | 2 | 2 |
| fleurs-1717 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 29 | 0 | 0 | 0 |
| fleurs-1718 | line-1 | tagalog |  |  |  | 21.88% | 9.45% | 32 | 4 | 0 | 3 |
| fleurs-1719 | line-1 | tagalog |  |  |  | 2.86% | 0.92% | 35 | 1 | 0 | 0 |
| fleurs-1720 | line-1 | tagalog |  |  |  | 10.00% | 1.61% | 20 | 2 | 0 | 0 |
| fleurs-1721 | line-1 | tagalog |  |  |  | 20.00% | 2.61% | 20 | 2 | 1 | 1 |
| fleurs-1722 | line-1 | tagalog |  |  |  | 6.06% | 1.79% | 33 | 2 | 0 | 0 |
| fleurs-1723 | line-1 | tagalog |  |  |  | 10.00% | 4.62% | 30 | 2 | 0 | 1 |
| fleurs-1724 | line-1 | tagalog |  |  |  | 20.00% | 1.89% | 20 | 2 | 2 | 0 |
| fleurs-1725 | line-1 | tagalog |  |  |  | 2.70% | 1.63% | 37 | 1 | 0 | 0 |
| fleurs-1726 | line-1 | tagalog |  |  |  | 11.43% | 2.12% | 35 | 4 | 0 | 0 |
| fleurs-1727 | line-1 | tagalog |  |  |  | 3.23% | 0.55% | 31 | 1 | 0 | 0 |
| fleurs-1728 | line-1 | tagalog |  |  |  | 9.09% | 0.89% | 22 | 1 | 1 | 0 |
| fleurs-1729 | line-1 | tagalog |  |  |  | 14.58% | 2.61% | 48 | 7 | 0 | 0 |
| fleurs-1730 | line-1 | tagalog |  |  |  | 21.43% | 11.27% | 42 | 5 | 4 | 0 |
| fleurs-1731 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 14 | 0 | 0 | 0 |
| fleurs-1732 | line-1 | tagalog |  |  |  | 29.41% | 24.14% | 34 | 7 | 3 | 0 |
| fleurs-1733 | line-1 | tagalog |  |  |  | 2.38% | 0.38% | 42 | 1 | 0 | 0 |
| fleurs-1734 | line-1 | tagalog |  |  |  | 16.67% | 6.05% | 36 | 6 | 0 | 0 |
| fleurs-1735 | line-1 | tagalog |  |  |  | 21.88% | 4.46% | 64 | 12 | 1 | 1 |
| fleurs-1736 | line-1 | tagalog |  |  |  | 15.38% | 1.37% | 13 | 1 | 0 | 1 |
| fleurs-1737 | line-1 | tagalog |  |  |  | 18.75% | 2.97% | 16 | 2 | 0 | 1 |
| fleurs-1738 | line-1 | tagalog |  |  |  | 14.29% | 2.56% | 21 | 3 | 0 | 0 |
| fleurs-1739 | line-1 | tagalog |  |  |  | 4.35% | 0.84% | 23 | 1 | 0 | 0 |
| fleurs-1740 | line-1 | tagalog |  |  |  | 9.52% | 0.94% | 21 | 1 | 1 | 0 |
| fleurs-1741 | line-1 | tagalog |  |  |  | 10.53% | 0.97% | 19 | 1 | 1 | 0 |
| fleurs-1742 | line-1 | tagalog |  |  |  | 14.81% | 1.20% | 27 | 2 | 2 | 0 |
| fleurs-1743 | line-1 | tagalog |  |  |  | 7.84% | 1.45% | 51 | 4 | 0 | 0 |
| fleurs-1744 | line-1 | tagalog |  |  |  | 11.76% | 1.87% | 17 | 1 | 0 | 1 |
| fleurs-1745 | line-1 | tagalog |  |  |  | 8.70% | 2.14% | 23 | 2 | 0 | 0 |
| fleurs-1746 | line-1 | tagalog |  |  |  | 10.53% | 1.74% | 19 | 2 | 0 | 0 |
| fleurs-1747 | line-1 | tagalog |  |  |  | 11.11% | 1.79% | 9 | 1 | 0 | 0 |
| fleurs-1748 | line-1 | tagalog |  |  |  | 35.71% | 4.23% | 14 | 2 | 1 | 2 |
| fleurs-1749 | line-1 | tagalog |  |  |  | 5.88% | 2.73% | 34 | 1 | 1 | 0 |
| fleurs-1750 | line-1 | tagalog |  |  |  | 6.67% | 1.22% | 15 | 1 | 0 | 0 |
| fleurs-1751 | line-1 | tagalog |  |  |  | 13.51% | 1.42% | 37 | 3 | 2 | 0 |
| fleurs-1752 | line-1 | tagalog |  |  |  | 4.55% | 2.34% | 22 | 0 | 0 | 1 |
| fleurs-1753 | line-1 | tagalog |  |  |  | 5.13% | 0.77% | 39 | 2 | 0 | 0 |
| fleurs-1754 | line-1 | tagalog |  |  |  | 18.52% | 5.23% | 27 | 4 | 0 | 1 |
| fleurs-1755 | line-1 | tagalog |  |  |  | 18.18% | 3.08% | 11 | 2 | 0 | 0 |
| fleurs-1756 | line-1 | tagalog |  |  |  | 8.57% | 2.12% | 35 | 3 | 0 | 0 |
| fleurs-1757 | line-1 | tagalog |  |  |  | 6.45% | 0.56% | 31 | 1 | 0 | 1 |
| fleurs-1758 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 22 | 0 | 0 | 0 |
| fleurs-1759 | line-1 | tagalog |  |  |  | 14.58% | 4.35% | 48 | 6 | 1 | 0 |
| fleurs-1760 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 17 | 0 | 0 | 0 |
| fleurs-1761 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 21 | 0 | 0 | 0 |
| fleurs-1762 | line-1 | tagalog |  |  |  | 5.88% | 2.44% | 17 | 1 | 0 | 0 |
| fleurs-1763 | line-1 | tagalog |  |  |  | 6.45% | 1.12% | 31 | 1 | 0 | 1 |
| fleurs-1764 | line-1 | tagalog |  |  |  | 17.65% | 3.64% | 17 | 2 | 0 | 1 |
| fleurs-1765 | line-1 | tagalog |  |  |  | 11.11% | 4.38% | 18 | 2 | 0 | 0 |
| fleurs-1766 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 35 | 0 | 0 | 0 |
| fleurs-1767 | line-1 | tagalog |  |  |  | 16.00% | 11.31% | 25 | 3 | 1 | 0 |
| fleurs-1768 | line-1 | tagalog |  |  |  | 3.33% | 1.84% | 30 | 1 | 0 | 0 |
| fleurs-1769 | line-1 | tagalog |  |  |  | 8.33% | 3.12% | 24 | 2 | 0 | 0 |
| fleurs-1770 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 14 | 0 | 0 | 0 |
| fleurs-1771 | line-1 | tagalog |  |  |  | 3.33% | 0.57% | 30 | 1 | 0 | 0 |
| fleurs-1772 | line-1 | tagalog |  |  |  | 16.67% | 2.60% | 12 | 1 | 1 | 0 |
| fleurs-1773 | line-1 | tagalog |  |  |  | 11.11% | 6.36% | 27 | 2 | 0 | 1 |
| fleurs-1774 | line-1 | tagalog |  |  |  | 4.76% | 1.29% | 42 | 2 | 0 | 0 |
| fleurs-1775 | line-1 | tagalog |  |  |  | 9.38% | 2.45% | 32 | 3 | 0 | 0 |
| fleurs-1776 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 23 | 0 | 0 | 0 |
| fleurs-1777 | line-1 | tagalog |  |  |  | 6.67% | 1.75% | 30 | 2 | 0 | 0 |
| fleurs-1778 | line-1 | tagalog |  |  |  | 7.69% | 1.35% | 13 | 1 | 0 | 0 |
| fleurs-1779 | line-1 | tagalog |  |  |  | 5.26% | 1.79% | 19 | 1 | 0 | 0 |
| fleurs-1780 | line-1 | tagalog |  |  |  | 16.00% | 3.77% | 25 | 3 | 0 | 1 |
| fleurs-1781 | line-1 | tagalog |  |  |  | 13.33% | 3.03% | 15 | 1 | 0 | 1 |
| fleurs-1782 | line-1 | tagalog |  |  |  | 2.50% | 0.47% | 40 | 1 | 0 | 0 |
| fleurs-1783 | line-1 | tagalog |  |  |  | 22.73% | 3.85% | 22 | 4 | 1 | 0 |
| fleurs-1784 | line-1 | tagalog |  |  |  | 9.09% | 1.43% | 44 | 3 | 1 | 0 |
| fleurs-1785 | line-1 | tagalog |  |  |  | 3.70% | 1.24% | 54 | 2 | 0 | 0 |
| fleurs-1786 | line-1 | tagalog |  |  |  | 7.41% | 1.26% | 27 | 1 | 0 | 1 |
| fleurs-1787 | line-1 | tagalog |  |  |  | 6.45% | 2.19% | 31 | 2 | 0 | 0 |
| fleurs-1788 | line-1 | tagalog |  |  |  | 5.26% | 0.43% | 38 | 1 | 1 | 0 |
| fleurs-1789 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 25 | 0 | 0 | 0 |
| fleurs-1790 | line-1 | tagalog |  |  |  | 24.32% | 8.52% | 37 | 7 | 1 | 1 |
| fleurs-1791 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 14 | 0 | 0 | 0 |
| fleurs-1792 | line-1 | tagalog |  |  |  | 5.56% | 1.01% | 18 | 1 | 0 | 0 |
| fleurs-1793 | line-1 | tagalog |  |  |  | 14.29% | 4.10% | 21 | 3 | 0 | 0 |
| fleurs-1794 | line-1 | tagalog |  |  |  | 5.26% | 1.53% | 19 | 1 | 0 | 0 |
| fleurs-1795 | line-1 | tagalog |  |  |  | 8.51% | 1.15% | 47 | 3 | 1 | 0 |
| fleurs-1796 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 21 | 0 | 0 | 0 |
| fleurs-1797 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 22 | 0 | 0 | 0 |
| fleurs-1798 | line-1 | tagalog |  |  |  | 10.00% | 2.92% | 30 | 3 | 0 | 0 |
| fleurs-1799 | line-1 | tagalog |  |  |  | 12.50% | 3.54% | 16 | 2 | 0 | 0 |
| fleurs-1800 | line-1 | tagalog |  |  |  | 4.35% | 0.66% | 23 | 1 | 0 | 0 |
| fleurs-1801 | line-1 | tagalog |  |  |  | 5.88% | 1.51% | 34 | 1 | 0 | 1 |
| fleurs-1802 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 12 | 0 | 0 | 0 |
| fleurs-1803 | line-1 | tagalog |  |  |  | 11.54% | 1.94% | 26 | 3 | 0 | 0 |
| fleurs-1804 | line-1 | tagalog |  |  |  | 16.28% | 4.21% | 43 | 5 | 0 | 2 |
| fleurs-1805 | line-1 | tagalog |  |  |  | 14.29% | 4.71% | 14 | 2 | 0 | 0 |
| fleurs-1806 | line-1 | tagalog |  |  |  | 7.14% | 1.35% | 42 | 3 | 0 | 0 |
| fleurs-1807 | line-1 | tagalog |  |  |  | 7.14% | 1.70% | 28 | 2 | 0 | 0 |
| fleurs-1808 | line-1 | tagalog |  |  |  | 4.76% | 1.55% | 21 | 1 | 0 | 0 |
| fleurs-1809 | line-1 | tagalog |  |  |  | 17.65% | 3.86% | 34 | 5 | 0 | 1 |
| fleurs-1810 | line-1 | tagalog |  |  |  | 8.57% | 0.93% | 35 | 2 | 0 | 1 |
| fleurs-1811 | line-1 | tagalog |  |  |  | 10.00% | 1.16% | 20 | 1 | 1 | 0 |
| fleurs-1812 | line-1 | tagalog |  |  |  | 25.71% | 10.55% | 35 | 6 | 1 | 2 |
| fleurs-1813 | line-1 | tagalog |  |  |  | 20.00% | 7.14% | 30 | 6 | 0 | 0 |
| fleurs-1814 | line-1 | tagalog |  |  |  | 3.57% | 0.65% | 28 | 1 | 0 | 0 |
| fleurs-1815 | line-1 | tagalog |  |  |  | 4.76% | 0.75% | 21 | 1 | 0 | 0 |
| fleurs-1816 | line-1 | tagalog |  |  |  | 20.69% | 2.60% | 29 | 4 | 2 | 0 |
| fleurs-1817 | line-1 | tagalog |  |  |  | 18.75% | 4.30% | 16 | 3 | 0 | 0 |
| fleurs-1818 | line-1 | tagalog |  |  |  | 23.81% | 5.17% | 21 | 4 | 1 | 0 |
| fleurs-1819 | line-1 | tagalog |  |  |  | 3.70% | 0.56% | 27 | 1 | 0 | 0 |
| fleurs-1820 | line-1 | tagalog |  |  |  | 18.18% | 6.15% | 22 | 4 | 0 | 0 |
| fleurs-1821 | line-1 | tagalog |  |  |  | 5.26% | 0.83% | 19 | 1 | 0 | 0 |
| fleurs-1822 | line-1 | tagalog |  |  |  | 28.12% | 5.15% | 32 | 7 | 1 | 1 |
| fleurs-1824 | line-1 | tagalog |  |  |  | 5.41% | 1.38% | 37 | 2 | 0 | 0 |
| fleurs-1825 | line-1 | tagalog |  |  |  | 5.88% | 3.74% | 17 | 0 | 0 | 1 |
| fleurs-1826 | line-1 | tagalog |  |  |  | 26.67% | 3.03% | 15 | 3 | 0 | 1 |
| fleurs-1827 | line-1 | tagalog |  |  |  | 8.70% | 12.73% | 23 | 2 | 0 | 0 |
| fleurs-1828 | line-1 | tagalog |  |  |  | 13.04% | 2.16% | 23 | 3 | 0 | 0 |
| fleurs-1829 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 35 | 0 | 0 | 0 |
| fleurs-1830 | line-1 | tagalog |  |  |  | 17.65% | 7.14% | 17 | 2 | 1 | 0 |
| fleurs-1831 | line-1 | tagalog |  |  |  | 6.67% | 1.69% | 30 | 2 | 0 | 0 |
| fleurs-1832 | line-1 | tagalog |  |  |  | 15.38% | 9.49% | 26 | 4 | 0 | 0 |
| fleurs-1833 | line-1 | tagalog |  |  |  | 6.25% | 1.81% | 32 | 2 | 0 | 0 |
| fleurs-1834 | line-1 | tagalog |  |  |  | 3.70% | 0.66% | 27 | 1 | 0 | 0 |
| fleurs-1835 | line-1 | tagalog |  |  |  | 12.50% | 2.76% | 32 | 4 | 0 | 0 |
| fleurs-1836 | line-1 | tagalog |  |  |  | 11.11% | 4.44% | 45 | 3 | 2 | 0 |
| fleurs-1837 | line-1 | tagalog |  |  |  | 11.54% | 1.20% | 26 | 2 | 0 | 1 |
| fleurs-1838 | line-1 | tagalog |  |  |  | 22.22% | 6.73% | 18 | 2 | 2 | 0 |
| fleurs-1839 | line-1 | tagalog |  |  |  | 15.38% | 1.47% | 13 | 1 | 1 | 0 |
| fleurs-1840 | line-1 | tagalog |  |  |  | 12.50% | 2.94% | 32 | 4 | 0 | 0 |
| fleurs-1841 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 27 | 0 | 0 | 0 |
| fleurs-1842 | line-1 | tagalog |  |  |  | 10.42% | 3.25% | 48 | 4 | 0 | 1 |
| fleurs-1843 | line-1 | tagalog |  |  |  | 23.33% | 8.11% | 30 | 5 | 0 | 2 |
| fleurs-1844 | line-1 | tagalog |  |  |  | 14.29% | 2.88% | 21 | 3 | 0 | 0 |
| fleurs-1845 | line-1 | tagalog |  |  |  | 19.23% | 7.45% | 26 | 4 | 1 | 0 |
| fleurs-1846 | line-1 | tagalog |  |  |  | 20.83% | 13.74% | 24 | 4 | 0 | 1 |
| fleurs-1847 | line-1 | tagalog |  |  |  | 3.33% | 0.61% | 30 | 1 | 0 | 0 |
| fleurs-1848 | line-1 | tagalog |  |  |  | 20.59% | 4.57% | 34 | 5 | 1 | 1 |
| fleurs-1849 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1850 | line-1 | tagalog |  |  |  | 12.00% | 4.35% | 25 | 3 | 0 | 0 |
| fleurs-1851 | line-1 | tagalog |  |  |  | 7.14% | 0.65% | 28 | 1 | 0 | 1 |
| fleurs-1852 | line-1 | tagalog |  |  |  | 36.51% | 15.92% | 63 | 13 | 1 | 9 |
| fleurs-1853 | line-1 | tagalog |  |  |  | 5.00% | 4.27% | 20 | 1 | 0 | 0 |
| fleurs-1854 | line-1 | tagalog |  |  |  | 15.79% | 2.80% | 19 | 2 | 0 | 1 |
| fleurs-1855 | line-1 | tagalog |  |  |  | 41.03% | 23.11% | 39 | 7 | 7 | 2 |
| fleurs-1856 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 31 | 0 | 0 | 0 |
| fleurs-1857 | line-1 | tagalog |  |  |  | 14.81% | 1.89% | 27 | 2 | 1 | 1 |
| fleurs-1858 | line-1 | tagalog |  |  |  | 8.70% | 2.13% | 23 | 2 | 0 | 0 |
| fleurs-1859 | line-1 | tagalog |  |  |  | 14.63% | 2.36% | 41 | 5 | 0 | 1 |
| fleurs-1860 | line-1 | tagalog |  |  |  | 12.50% | 2.27% | 16 | 1 | 1 | 0 |
| fleurs-1861 | line-1 | tagalog |  |  |  | 27.27% | 4.48% | 22 | 4 | 0 | 2 |
| fleurs-1862 | line-1 | tagalog |  |  |  | 5.41% | 1.40% | 37 | 2 | 0 | 0 |
| fleurs-1863 | line-1 | tagalog |  |  |  | 9.52% | 4.55% | 42 | 2 | 2 | 0 |
| fleurs-1864 | line-1 | tagalog |  |  |  | 10.81% | 2.88% | 37 | 4 | 0 | 0 |
| fleurs-1865 | line-1 | tagalog |  |  |  | 15.62% | 5.67% | 32 | 4 | 1 | 0 |
| fleurs-1866 | line-1 | tagalog |  |  |  | 5.00% | 0.81% | 20 | 1 | 0 | 0 |
| fleurs-1867 | line-1 | tagalog |  |  |  | 10.71% | 3.11% | 28 | 3 | 0 | 0 |
| fleurs-1868 | line-1 | tagalog |  |  |  | 6.90% | 1.68% | 29 | 2 | 0 | 0 |
| fleurs-1869 | line-1 | tagalog |  |  |  | 15.62% | 6.25% | 32 | 4 | 0 | 1 |
| fleurs-1870 | line-1 | tagalog |  |  |  | 17.65% | 6.32% | 17 | 2 | 1 | 0 |
| fleurs-1871 | line-1 | tagalog |  |  |  | 7.69% | 2.56% | 13 | 1 | 0 | 0 |
| fleurs-1872 | line-1 | tagalog |  |  |  | 25.81% | 5.61% | 31 | 6 | 1 | 1 |
| fleurs-1873 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 26 | 0 | 0 | 0 |
| fleurs-1874 | line-1 | tagalog |  |  |  | 9.68% | 2.89% | 31 | 3 | 0 | 0 |
| fleurs-1875 | line-1 | tagalog |  |  |  | 4.55% | 9.82% | 22 | 0 | 1 | 0 |
| fleurs-1876 | line-1 | tagalog |  |  |  | 11.11% | 1.74% | 18 | 2 | 0 | 0 |
| fleurs-1877 | line-1 | tagalog |  |  |  | 10.81% | 3.51% | 37 | 3 | 0 | 1 |
| fleurs-1878 | line-1 | tagalog |  |  |  | 11.11% | 3.23% | 36 | 4 | 0 | 0 |
| fleurs-1879 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 18 | 0 | 0 | 0 |
| fleurs-1880 | line-1 | tagalog |  |  |  | 14.29% | 2.35% | 14 | 1 | 0 | 1 |
| fleurs-1881 | line-1 | tagalog |  |  |  | 7.14% | 2.21% | 28 | 2 | 0 | 0 |
| fleurs-1882 | line-1 | tagalog |  |  |  | 15.62% | 4.79% | 32 | 4 | 1 | 0 |
| fleurs-1883 | line-1 | tagalog |  |  |  | 8.00% | 5.71% | 25 | 0 | 0 | 2 |
| fleurs-1884 | line-1 | tagalog |  |  |  | 9.09% | 1.95% | 22 | 2 | 0 | 0 |
| fleurs-1885 | line-1 | tagalog |  |  |  | 45.00% | 46.32% | 20 | 5 | 0 | 4 |
| fleurs-1886 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 23 | 0 | 0 | 0 |
| fleurs-1887 | line-1 | tagalog |  |  |  | 11.11% | 1.49% | 18 | 2 | 0 | 0 |
| fleurs-1888 | line-1 | tagalog |  |  |  | 31.03% | 26.23% | 29 | 2 | 7 | 0 |
| fleurs-1889 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 16 | 0 | 0 | 0 |
| fleurs-1890 | line-1 | tagalog |  |  |  | 10.00% | 1.36% | 20 | 2 | 0 | 0 |
| fleurs-1891 | line-1 | tagalog |  |  |  | 56.25% | 12.15% | 16 | 7 | 0 | 2 |
| fleurs-1892 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 33 | 0 | 0 | 0 |
| fleurs-1893 | line-1 | tagalog |  |  |  | 9.38% | 3.31% | 32 | 3 | 0 | 0 |
| fleurs-1894 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 19 | 0 | 0 | 0 |
| fleurs-1895 | line-1 | tagalog |  |  |  | 18.18% | 4.17% | 22 | 4 | 0 | 0 |
| fleurs-1896 | line-1 | tagalog |  |  |  | 19.05% | 3.91% | 42 | 7 | 1 | 0 |
| fleurs-1897 | line-1 | tagalog |  |  |  | 17.65% | 6.19% | 17 | 2 | 1 | 0 |
| fleurs-1898 | line-1 | tagalog |  |  |  | 2.94% | 1.94% | 34 | 1 | 0 | 0 |
| fleurs-1899 | line-1 | tagalog |  |  |  | 10.26% | 1.35% | 39 | 3 | 1 | 0 |
| fleurs-1900 | line-1 | tagalog |  |  |  | 4.35% | 2.19% | 23 | 0 | 1 | 0 |
| fleurs-1901 | line-1 | tagalog |  |  |  | 13.51% | 3.65% | 37 | 4 | 0 | 1 |
| fleurs-1902 | line-1 | tagalog |  |  |  | 33.33% | 7.46% | 12 | 3 | 0 | 1 |
| fleurs-1903 | line-1 | tagalog |  |  |  | 4.76% | 0.67% | 21 | 1 | 0 | 0 |
| fleurs-1904 | line-1 | tagalog |  |  |  | 8.70% | 1.47% | 23 | 2 | 0 | 0 |
| fleurs-1905 | line-1 | tagalog |  |  |  | 22.22% | 7.96% | 18 | 4 | 0 | 0 |
| fleurs-1906 | line-1 | tagalog |  |  |  | 14.29% | 8.24% | 14 | 1 | 0 | 1 |
| fleurs-1907 | line-1 | tagalog |  |  |  | 35.29% | 5.36% | 17 | 5 | 1 | 0 |
| fleurs-1908 | line-1 | tagalog |  |  |  | 6.67% | 2.20% | 15 | 1 | 0 | 0 |
| fleurs-1909 | line-1 | tagalog |  |  |  | 7.69% | 1.80% | 26 | 2 | 0 | 0 |
| fleurs-1910 | line-1 | tagalog |  |  |  | 9.09% | 1.56% | 11 | 1 | 0 | 0 |
| fleurs-1911 | line-1 | tagalog |  |  |  | 13.33% | 2.13% | 30 | 3 | 0 | 1 |
| fleurs-1912 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 20 | 0 | 0 | 0 |
| fleurs-1913 | line-1 | tagalog |  |  |  | 3.85% | 2.70% | 26 | 1 | 0 | 0 |
| fleurs-1914 | line-1 | tagalog |  |  |  | 29.41% | 3.36% | 17 | 3 | 1 | 1 |
| fleurs-1915 | line-1 | tagalog |  |  |  | 11.54% | 8.92% | 26 | 3 | 0 | 0 |
| fleurs-1916 | line-1 | tagalog |  |  |  | 12.50% | 6.47% | 32 | 2 | 1 | 1 |
| fleurs-1917 | line-1 | tagalog |  |  |  | 20.00% | 8.40% | 20 | 3 | 0 | 1 |
| fleurs-1918 | line-1 | tagalog |  |  |  | 20.00% | 2.37% | 25 | 4 | 0 | 1 |
| fleurs-1919 | line-1 | tagalog |  |  |  | 16.00% | 2.04% | 25 | 3 | 1 | 0 |
| fleurs-1920 | line-1 | tagalog |  |  |  | 4.00% | 1.29% | 25 | 1 | 0 | 0 |
| fleurs-1921 | line-1 | tagalog |  |  |  | 8.70% | 1.49% | 23 | 2 | 0 | 0 |
| fleurs-1922 | line-1 | tagalog |  |  |  | 30.77% | 8.14% | 26 | 8 | 0 | 0 |
| fleurs-1923 | line-1 | tagalog |  |  |  | 19.57% | 4.10% | 46 | 9 | 0 | 0 |
| fleurs-1924 | line-1 | tagalog |  |  |  | 48.15% | 32.47% | 27 | 8 | 0 | 5 |
| fleurs-1925 | line-1 | tagalog |  |  |  | 23.81% | 3.97% | 21 | 4 | 0 | 1 |
| fleurs-1926 | line-1 | tagalog |  |  |  | 18.75% | 4.85% | 16 | 3 | 0 | 0 |
| fleurs-1927 | line-1 | tagalog |  |  |  | 4.17% | 0.64% | 24 | 1 | 0 | 0 |
| fleurs-1928 | line-1 | tagalog |  |  |  | 29.41% | 21.01% | 17 | 4 | 1 | 0 |
| fleurs-1929 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1930 | line-1 | tagalog |  |  |  | 11.11% | 1.80% | 18 | 2 | 0 | 0 |
| fleurs-1931 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 36 | 0 | 0 | 0 |
| fleurs-1932 | line-1 | tagalog |  |  |  | 10.53% | 2.87% | 57 | 5 | 1 | 0 |
| fleurs-1933 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 32 | 0 | 0 | 0 |
| fleurs-1934 | line-1 | tagalog |  |  |  | 7.41% | 1.32% | 27 | 2 | 0 | 0 |
| fleurs-1935 | line-1 | tagalog |  |  |  | 18.75% | 2.94% | 16 | 2 | 1 | 0 |
| fleurs-1936 | line-1 | tagalog |  |  |  | 6.00% | 2.55% | 50 | 2 | 0 | 1 |
| fleurs-1937 | line-1 | tagalog |  |  |  | 11.59% | 4.20% | 69 | 7 | 1 | 0 |
| fleurs-1938 | line-1 | tagalog |  |  |  | 8.33% | 3.27% | 24 | 1 | 0 | 1 |
| fleurs-1939 | line-1 | tagalog |  |  |  | 19.23% | 1.71% | 26 | 3 | 1 | 1 |
| fleurs-1940 | line-1 | tagalog |  |  |  | 12.12% | 1.95% | 33 | 4 | 0 | 0 |
| fleurs-1941 | line-1 | tagalog |  |  |  | 9.09% | 5.88% | 11 | 0 | 0 | 1 |
| fleurs-1942 | line-1 | tagalog |  |  |  | 10.81% | 2.42% | 37 | 3 | 0 | 1 |
| fleurs-1943 | line-1 | tagalog |  |  |  | 10.71% | 1.76% | 28 | 3 | 0 | 0 |
| fleurs-1944 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 28 | 0 | 0 | 0 |
| fleurs-1945 | line-1 | tagalog |  |  |  | 11.76% | 1.05% | 17 | 1 | 0 | 1 |
| fleurs-1946 | line-1 | tagalog |  |  |  | 8.33% | 4.37% | 36 | 1 | 1 | 1 |
| fleurs-1947 | line-1 | tagalog |  |  |  | 4.35% | 0.78% | 23 | 1 | 0 | 0 |
| fleurs-1948 | line-1 | tagalog |  |  |  | 18.18% | 7.04% | 33 | 4 | 1 | 1 |
| fleurs-1949 | line-1 | tagalog |  |  |  | 16.67% | 4.00% | 18 | 3 | 0 | 0 |
| fleurs-1950 | line-1 | tagalog |  |  |  | 5.88% | 2.86% | 34 | 2 | 0 | 0 |
| fleurs-1951 | line-1 | tagalog |  |  |  | 3.57% | 1.32% | 28 | 1 | 0 | 0 |
| fleurs-1952 | line-1 | tagalog |  |  |  | 19.35% | 3.28% | 31 | 5 | 0 | 1 |
| fleurs-1953 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 11 | 0 | 0 | 0 |
| fleurs-1954 | line-1 | tagalog |  |  |  | 10.34% | 1.53% | 29 | 3 | 0 | 0 |
| fleurs-1955 | line-1 | tagalog |  |  |  | 4.76% | 0.91% | 21 | 1 | 0 | 0 |
| fleurs-1956 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 33 | 0 | 0 | 0 |
| fleurs-1957 | line-1 | tagalog |  |  |  | 16.67% | 1.32% | 12 | 1 | 1 | 0 |
| fleurs-1958 | line-1 | tagalog |  |  |  | 4.35% | 0.86% | 23 | 1 | 0 | 0 |
| fleurs-1959 | line-1 | tagalog |  |  |  | 10.53% | 3.23% | 19 | 2 | 0 | 0 |
| fleurs-1960 | line-1 | tagalog |  |  |  | 7.32% | 1.74% | 41 | 3 | 0 | 0 |
| fleurs-1961 | line-1 | tagalog |  |  |  | 6.82% | 0.66% | 44 | 2 | 0 | 1 |
| fleurs-1962 | line-1 | tagalog |  |  |  | 10.53% | 6.45% | 19 | 2 | 0 | 0 |
| fleurs-1963 | line-1 | tagalog |  |  |  | 24.24% | 3.12% | 33 | 6 | 2 | 0 |
| fleurs-1964 | line-1 | tagalog |  |  |  | 7.41% | 3.01% | 27 | 1 | 0 | 1 |
| fleurs-1965 | line-1 | tagalog |  |  |  | 3.85% | 0.66% | 26 | 1 | 0 | 0 |
| fleurs-1966 | line-1 | tagalog |  |  |  | 5.56% | 0.88% | 18 | 1 | 0 | 0 |
| fleurs-1967 | line-1 | tagalog |  |  |  | 11.43% | 6.17% | 35 | 3 | 0 | 1 |
| fleurs-1968 | line-1 | tagalog |  |  |  | 2.38% | 0.43% | 42 | 1 | 0 | 0 |
| fleurs-1969 | line-1 | tagalog |  |  |  | 6.67% | 1.67% | 30 | 2 | 0 | 0 |
| fleurs-1970 | line-1 | tagalog |  |  |  | 16.13% | 2.66% | 31 | 4 | 1 | 0 |
| fleurs-1971 | line-1 | tagalog |  |  |  | 13.33% | 1.78% | 45 | 4 | 2 | 0 |
| fleurs-1972 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 18 | 0 | 0 | 0 |
| fleurs-1973 | line-1 | tagalog |  |  |  | 9.38% | 5.10% | 32 | 2 | 1 | 0 |
| fleurs-1974 | line-1 | tagalog |  |  |  | 23.08% | 2.17% | 13 | 2 | 0 | 1 |
| fleurs-1975 | line-1 | tagalog |  |  |  | 4.35% | 0.70% | 23 | 1 | 0 | 0 |
| fleurs-1976 | line-1 | tagalog |  |  |  | 16.67% | 4.93% | 24 | 4 | 0 | 0 |
| fleurs-1977 | line-1 | tagalog |  |  |  | 13.64% | 4.55% | 22 | 2 | 0 | 1 |
| fleurs-1978 | line-1 | tagalog |  |  |  | 16.67% | 1.41% | 12 | 1 | 0 | 1 |
| fleurs-1979 | line-1 | tagalog |  |  |  | 23.81% | 9.91% | 21 | 3 | 0 | 2 |
| fleurs-1980 | line-1 | tagalog |  |  |  | 20.00% | 12.97% | 25 | 4 | 1 | 0 |
| fleurs-1981 | line-1 | tagalog |  |  |  | 13.64% | 6.82% | 22 | 2 | 0 | 1 |
| fleurs-1982 | line-1 | tagalog |  |  |  | 22.73% | 3.52% | 22 | 3 | 1 | 1 |
| fleurs-1983 | line-1 | tagalog |  |  |  | 7.50% | 0.77% | 40 | 2 | 0 | 1 |
| fleurs-1984 | line-1 | tagalog |  |  |  | 7.89% | 0.91% | 38 | 2 | 1 | 0 |
| fleurs-1985 | line-1 | tagalog |  |  |  | 4.88% | 0.84% | 41 | 2 | 0 | 0 |
| fleurs-1986 | line-1 | tagalog |  |  |  | 27.27% | 9.02% | 22 | 4 | 0 | 2 |
| fleurs-1987 | line-1 | tagalog |  |  |  | 11.76% | 0.92% | 17 | 1 | 0 | 1 |
| fleurs-1988 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 22 | 0 | 0 | 0 |
| fleurs-1989 | line-1 | tagalog |  |  |  | 23.68% | 17.17% | 38 | 6 | 1 | 2 |
| fleurs-1990 | line-1 | tagalog |  |  |  | 2.22% | 0.36% | 45 | 1 | 0 | 0 |
| fleurs-1991 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 19 | 0 | 0 | 0 |
| fleurs-1992 | line-1 | tagalog |  |  |  | 19.23% | 3.18% | 26 | 4 | 0 | 1 |
| fleurs-1993 | line-1 | tagalog |  |  |  | 19.05% | 2.74% | 21 | 3 | 0 | 1 |
| fleurs-1994 | line-1 | tagalog |  |  |  | 9.09% | 1.64% | 22 | 2 | 0 | 0 |
| fleurs-1995 | line-1 | tagalog |  |  |  | 23.53% | 4.72% | 34 | 6 | 1 | 1 |
| fleurs-1996 | line-1 | tagalog |  |  |  | 15.62% | 3.45% | 32 | 5 | 0 | 0 |
| fleurs-1997 | line-1 | tagalog |  |  |  | 27.78% | 5.42% | 36 | 9 | 0 | 1 |
| fleurs-1998 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 24 | 0 | 0 | 0 |
| fleurs-1999 | line-1 | tagalog |  |  |  | 4.00% | 0.66% | 25 | 1 | 0 | 0 |
| fleurs-2000 | line-1 | tagalog |  |  |  | 3.33% | 0.53% | 30 | 1 | 0 | 0 |
| fleurs-2001 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 34 | 0 | 0 | 0 |
| fleurs-2002 | line-1 | tagalog |  |  |  | 4.17% | 1.47% | 24 | 1 | 0 | 0 |
| fleurs-2003 | line-1 | tagalog |  |  |  | 0.00% | 0.00% | 20 | 0 | 0 | 0 |
| fleurs-2004 | line-1 | tagalog |  |  |  | 12.00% | 2.80% | 25 | 3 | 0 | 0 |
| fleurs-2005 | line-1 | tagalog |  |  |  | 6.67% | 3.23% | 15 | 0 | 1 | 0 |
| fleurs-2006 | line-1 | tagalog |  |  |  | 4.35% | 0.78% | 23 | 1 | 0 | 0 |
| fleurs-2007 | line-1 | tagalog |  |  |  | 18.52% | 4.20% | 27 | 4 | 1 | 0 |
| fleurs-2008 | line-1 | tagalog |  |  |  | 2.33% | 0.39% | 43 | 1 | 0 | 0 |
| fleurs-2009 | line-1 | tagalog |  |  |  | 4.55% | 0.84% | 44 | 2 | 0 | 0 |

The raw reference and hypothesis of each item are in the JSON report, unchanged.

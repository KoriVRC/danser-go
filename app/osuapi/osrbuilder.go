package osuapi

import (
	"bytes"
	"encoding/binary"
	"time"
)

func buildOSRString(s string) []byte {
	if s == "" {
		return []byte{0x00}
	}

	b := bytes.Buffer{}
	b.WriteByte(0x0b)

	v := uint64(len(s))
	for v >= 0x80 {
		b.WriteByte(byte(v) | 0x80)
		v >>= 7
	}
	b.WriteByte(byte(v))

	b.WriteString(s)
	return b.Bytes()
}

func BuildOSR(score Score, lzmaData []byte, beatmapMD5 string, mode int) []byte {
	buf := new(bytes.Buffer)

	// Game mode
	buf.WriteByte(byte(mode))

	// version
	binary.Write(buf, binary.LittleEndian, uint32(20210520))

	// Beatmap MD5
	buf.Write(buildOSRString(beatmapMD5))

	// Username
	buf.Write(buildOSRString(score.User.Username))

	// Replay MD5 (empty)
	buf.Write(buildOSRString(""))

	// Hit counts
	binary.Write(buf, binary.LittleEndian, uint16(score.Statistics["count_300"]))
	binary.Write(buf, binary.LittleEndian, uint16(score.Statistics["count_100"]))
	binary.Write(buf, binary.LittleEndian, uint16(score.Statistics["count_50"]))
	binary.Write(buf, binary.LittleEndian, uint16(score.Statistics["count_geki"]))
	binary.Write(buf, binary.LittleEndian, uint16(score.Statistics["count_katu"]))
	binary.Write(buf, binary.LittleEndian, uint16(score.Statistics["count_miss"]))

	// Total score
	binary.Write(buf, binary.LittleEndian, uint32(score.TotalScore))

	// Max combo
	binary.Write(buf, binary.LittleEndian, uint16(score.MaxCombo))

	// Perfect
	perfect := byte(0)
	if score.Perfect {
		perfect = 1
	}
	buf.WriteByte(perfect)

	// Mods
	binary.Write(buf, binary.LittleEndian, uint32(ModsToMask(score.Mods)))

	// Life graph (empty)
	buf.Write(buildOSRString(""))

	// Timestamp
	t, _ := time.Parse(time.RFC3339, score.CreatedAt)
	binary.Write(buf, binary.LittleEndian, WindowsTicks(t))

	// LZMA data
	binary.Write(buf, binary.LittleEndian, uint32(len(lzmaData)))
	buf.Write(lzmaData)

	// Online score ID
	binary.Write(buf, binary.LittleEndian, score.ID)

	return buf.Bytes()
}

func ModsToMask(mods []ScoreMod) int {
	mask := 0
	for _, m := range mods {
		switch m.Acronym {
		case "NF":
			mask |= 1
		case "EZ":
			mask |= 2
		case "TD":
			mask |= 4
		case "HD":
			mask |= 8
		case "HR":
			mask |= 16
		case "SD":
			mask |= 32
		case "DT":
			mask |= 64
		case "RX":
			mask |= 128
		case "HT":
			mask |= 256
		case "NC":
			mask |= 512 | 64
		case "FL":
			mask |= 1024
		case "AT":
			mask |= 2048
		case "SO":
			mask |= 4096
		case "RX2":
			mask |= 8192
		case "PF":
			mask |= 16384 | 32
		}
	}
	return mask
}

// WindowsTicks returns the number of 100-nanosecond intervals since January 1, 0001.
func WindowsTicks(t time.Time) int64 {
	// The epoch for Windows File Time is January 1, 1601.
	// But the .osr format uses January 1, 0001.
	// There are 62135596800 seconds between 0001-01-01 and 1970-01-01.
	return (t.Unix() + 62135596800) * 10000000
}

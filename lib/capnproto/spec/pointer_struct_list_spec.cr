require "./spec_helper"

from_segment = ->(byte_offset : UInt32, bytes : Bytes) do
  segments = [] of CapnProto::Segment
  segment = CapnProto::Segment.new(segments, bytes)
  CapnProto::Pointer::StructList.parse_from(
    segment, byte_offset, segment.u64(byte_offset)
  )
end

from_segments = ->(byte_offset : UInt32, chunks : Array(Bytes)) do
  segments = [] of CapnProto::Segment
  chunks.each { |chunk| CapnProto::Segment.new(segments, chunk) }
  segment = segments[0]
  CapnProto::Pointer::StructList.parse_from(
    segment, byte_offset, segment.u64(byte_offset)
  )
end

describe CapnProto::Pointer::StructList do
  it "reads struct values from a struct list region" do
    p = from_segment.call(0_u32, Bytes[
      0x01, 0x00, 0x00, 0x00, 0x1f, 0x01, 0x00, 0x00,
      0x0c, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, 0x00,
      0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
      0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22,
      0x25, 0x00, 0x00, 0x00, 0x42, 0x00, 0x00, 0x00,
      0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33,
      0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44,
      0x1d, 0x00, 0x00, 0x00, 0x42, 0x00, 0x00, 0x00,
      0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
      0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
      0x15, 0x00, 0x00, 0x00, 0x42, 0x00, 0x00, 0x00,
      0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
      0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
      0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
      'H'.ord, 'e'.ord, 'l'.ord, 'l'.ord, 'o'.ord, ' '.ord, 'A'.ord, 0x00,
      'H'.ord, 'e'.ord, 'l'.ord, 'l'.ord, 'o'.ord, ' '.ord, 'B'.ord, 0x00,
      'H'.ord, 'e'.ord, 'l'.ord, 'l'.ord, 'o'.ord, ' '.ord, 'C'.ord, 0x00,
      'L'.ord, 'o'.ord, 'n'.ord, 'e'.ord, 'l'.ord, 'y'.ord, ' '.ord, 'D'.ord,
    ])

    p0 = p[0].not_nil!
    p0.u64(0x0).should eq 0x1111111111111111_u64
    p0.u64(0x8).should eq 0x2222222222222222_u64
    p0.u64(0x10).should eq 0 # outside the data region
    p0.text(0).should eq "Hello A"
    p0.text(1).should eq "" # outside the pointers region

    p1 = p[1].not_nil!
    p1.u64(0x0).should eq 0x3333333333333333_u64
    p1.u64(0x8).should eq 0x4444444444444444_u64
    p1.u64(0x10).should eq 0 # outside the data region
    p1.text(0).should eq "Hello B"
    p1.text(1).should eq "" # outside the pointers region

    p2 = p[2].not_nil!
    p2.u64(0x0).should eq 0x5555555555555555_u64
    p2.u64(0x8).should eq 0x6666666666666666_u64
    p2.u64(0x10).should eq 0 # outside the data region
    p2.text(0).should eq "Hello C"
    p2.text(1).should eq "" # outside the pointers region

    p[3].should eq nil # outside the list region

    first_words = [] of UInt64
    p.each { |s| first_words << s.u64(0x0) }
    first_words.should eq [
      0x1111111111111111_u64,
      0x3333333333333333_u64,
      0x5555555555555555_u64,
    ]
  end

  it "can point to a struct list region via a far pointer" do
    p = from_segments.call(0_u32, [
      Bytes[
        0x12, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
      ],
      Bytes[
        'T'.ord, 'h'.ord, 'e'.ord, 'r'.ord, 'e'.ord, '\''.ord, 's'.ord, ' '.ord,
        'n'.ord, 'o'.ord, 't'.ord, 'h'.ord, 'i'.ord, 'n'.ord, 'g'.ord, ' '.ord,
        'm'.ord, 'e'.ord, 'a'.ord, 'n'.ord, 'i'.ord, 'n'.ord, 'g'.ord,
        'f'.ord, 'u'.ord, 'l'.ord, ' '.ord, 'i'.ord, 'n'.ord, ' '.ord,
        't'.ord, 'h'.ord, 'i'.ord, 's'.ord, ' '.ord,
        'm'.ord, 'i'.ord, 'd'.ord, 'd'.ord, 'l'.ord, 'e'.ord, ' '.ord,
        's'.ord, 'e'.ord, 'g'.ord, 'm'.ord, 'e'.ord, 'n'.ord, 't'.ord, '.'.ord,
        ' '.ord, 'I'.ord, 't'.ord, '\''.ord, 's'.ord, ' '.ord,
        'j'.ord, 'u'.ord, 's'.ord, 't'.ord, ' '.ord, 'a'.ord, ' '.ord,
        'p'.ord, 'l'.ord, 'a'.ord, 'c'.ord, 'e'.ord,
        'h'.ord, 'o'.ord, 'l'.ord, 'd'.ord, 'e'.ord, 'r'.ord, ' '.ord,
        'i'.ord, 'n'.ord, ' '.ord, 'b'.ord, 'e'.ord, 't'.ord, 'w'.ord,
        'e'.ord, 'e'.ord, 'n'.ord, ' '.ord, 't'.ord, 'h'.ord, 'e'.ord, ' '.ord,
        'o'.ord, 't'.ord, 'h'.ord, 'e'.ord, 'r'.ord, ' '.ord,
        't'.ord, 'w'.ord, 'o'.ord, '.'.ord,
      ],
      Bytes[
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
        0x01, 0x00, 0x00, 0x00, 0x27, 0x00, 0x00, 0x00,
        0x08, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
        0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22,
        0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33,
        0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44,
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
      ]
    ])

    p[0].not_nil!.u64(0x0).should eq 0x1111111111111111_u64
    p[0].not_nil!.u64(0x8).should eq 0x2222222222222222_u64
    p[0].not_nil!.u64(0x10).should eq 0 # outside the data region
    p[1].not_nil!.u64(0x0).should eq 0x3333333333333333_u64
    p[1].not_nil!.u64(0x8).should eq 0x4444444444444444_u64
    p[1].not_nil!.u64(0x10).should eq 0 # outside the data region
  end

  it "can point to a byte region via a double-far pointer" do
    p = from_segments.call(0_u32, [
      Bytes[
        0x26, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
      ],
      Bytes[
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
        0x12, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x00, 0x27, 0x00, 0x00, 0x00,
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
      ],
      Bytes[
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
        0x08, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
        0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22,
        0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33,
        0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44,
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
        0xde, 0xad, 0xbe, 0xef, 0xde, 0xad, 0xbe, 0xef,
      ]
    ])

    p[0].not_nil!.u64(0x0).should eq 0x1111111111111111_u64
    p[0].not_nil!.u64(0x8).should eq 0x2222222222222222_u64
    p[0].not_nil!.u64(0x10).should eq 0 # outside the data region
    p[1].not_nil!.u64(0x0).should eq 0x3333333333333333_u64
    p[1].not_nil!.u64(0x8).should eq 0x4444444444444444_u64
    p[1].not_nil!.u64(0x10).should eq 0 # outside the data region
  end
end

import Testing

@testable import PlaybackEngine

@Suite("WebVTTParser")
struct WebVTTParserTests {

    @Test("Parses basic WebVTT with WEBVTT header")
    func basicWebVTT() {
        let content = """
        WEBVTT

        1
        00:00:01.000 --> 00:00:04.000
        Hello, world!

        2
        00:00:05.000 --> 00:00:08.000
        This is a test.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 2)
        #expect(cues[0].text == "Hello, world!")
        #expect(cues[0].startTime == 1.0)
        #expect(cues[0].endTime == 4.0)
        #expect(cues[1].text == "This is a test.")
        #expect(cues[1].startTime == 5.0)
        #expect(cues[1].endTime == 8.0)
    }

    @Test("Parses SRT format with comma separators")
    func srtFormat() {
        let content = """
        1
        00:01:23,456 --> 00:01:25,789
        SRT subtitle line.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 1)
        #expect(cues[0].startTime == 83.456)
        #expect(cues[0].endTime == 85.789)
        #expect(cues[0].text == "SRT subtitle line.")
    }

    @Test("Strips HTML tags from cue text")
    func htmlTagStripping() {
        let content = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        <b>Bold</b> and <i>italic</i> text.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Bold and italic text.")
    }

    @Test("Handles multi-line cue text")
    func multiLineCue() {
        let content = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        Line one.
        Line two.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Line one.\nLine two.")
    }

    @Test("Returns sorted cues by start time")
    func sortedOutput() {
        let content = """
        WEBVTT

        00:00:05.000 --> 00:00:08.000
        Second cue.

        00:00:01.000 --> 00:00:04.000
        First cue.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 2)
        #expect(cues[0].text == "First cue.")
        #expect(cues[1].text == "Second cue.")
    }

    @Test("Parses short MM:SS.mmm timestamps")
    func shortTimestamps() {
        let content = """
        WEBVTT

        01:30.500 --> 02:00.000
        Short timestamp format.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 1)
        #expect(cues[0].startTime == 90.5)
        #expect(cues[0].endTime == 120.0)
    }

    @Test("Skips blocks without timestamp lines")
    func skipsNonCueBlocks() {
        let content = """
        WEBVTT
        Kind: captions

        NOTE This is a comment block

        00:00:01.000 --> 00:00:04.000
        Actual cue.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Actual cue.")
    }

    @Test("Handles empty input")
    func emptyInput() {
        let cues = WebVTTParser.parse("")
        #expect(cues.isEmpty)
    }

    @Test("Skips cues with empty text after tag stripping")
    func emptyCueAfterStripping() {
        let content = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        <b></b>

        00:00:05.000 --> 00:00:08.000
        Real text.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Real text.")
    }

    @Test("Handles Windows-style line endings")
    func windowsLineEndings() {
        let content = "WEBVTT\r\n\r\n00:00:01.000 --> 00:00:04.000\r\nWindows line endings.\r\n"
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Windows line endings.")
    }

    @Test("Handles position metadata after timestamp")
    func positionMetadata() {
        let content = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000 position:50% align:center
        Positioned cue.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Positioned cue.")
        #expect(cues[0].endTime == 4.0)
    }

    @Test("Handles large hour values in timestamps")
    func largeHourTimestamps() {
        let content = """
        WEBVTT

        02:30:00.000 --> 02:30:30.000
        Late in the movie.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 1)
        #expect(cues[0].startTime == 9000.0)
        #expect(cues[0].endTime == 9030.0)
    }

    @Test("Strips nested and self-closing HTML tags")
    func nestedHTMLTags() {
        let content = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        <b><i>Nested</i></b> and <br/> break.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Nested and  break.")
    }

    @Test("Handles cues without numeric identifiers")
    func cuesWithoutIdentifiers() {
        let content = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        No identifier.

        00:00:05.000 --> 00:00:08.000
        Also no identifier.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 2)
        #expect(cues[0].text == "No identifier.")
        #expect(cues[1].text == "Also no identifier.")
    }

    @Test("Handles only carriage return line endings")
    func carriageReturnOnly() {
        let content = "WEBVTT\r\r00:00:01.000 --> 00:00:04.000\rCR only.\r"
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "CR only.")
    }

    @Test("Parses SRT with numbered cues and no header")
    func srtFullFormat() {
        let content = """
        1
        00:00:01,000 --> 00:00:04,000
        First subtitle.

        2
        00:00:05,500 --> 00:00:08,200
        Second subtitle.

        3
        00:00:10,000 --> 00:00:12,750
        Third subtitle.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 3)
        #expect(cues[0].startTime == 1.0)
        #expect(cues[0].endTime == 4.0)
        #expect(cues[0].text == "First subtitle.")
        #expect(cues[1].startTime == 5.5)
        #expect(cues[1].endTime == 8.2)
        #expect(cues[1].text == "Second subtitle.")
        #expect(cues[2].startTime == 10.0)
        #expect(cues[2].endTime == 12.75)
        #expect(cues[2].text == "Third subtitle.")
    }

    @Test("Handles input with only WEBVTT header and no cues")
    func headerOnly() {
        let content = "WEBVTT\n\n"
        let cues = WebVTTParser.parse(content)
        #expect(cues.isEmpty)
    }

    @Test("Handles multiple blank lines between cues")
    func multipleBlankLines() {
        let content = """
        WEBVTT


        00:00:01.000 --> 00:00:04.000
        First.



        00:00:05.000 --> 00:00:08.000
        Second.
        """
        let cues = WebVTTParser.parse(content)
        #expect(cues.count == 2)
        #expect(cues[0].text == "First.")
        #expect(cues[1].text == "Second.")
    }
}

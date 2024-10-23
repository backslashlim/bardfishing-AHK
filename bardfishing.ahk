if not DirExist('midi')
    DirCreate('midi')

; grabs all midi files from an adjacent directory and creates a GUI
; with a drop down list so the user can select the song to play
SongList := []
loop files "midi\*.mid"
    SongList.InsertAt(0, A_LoopFileName)

SongSelector := Gui()
Dropdown := SongSelector.AddDDL(,SongList)

j::
{
    ShowMenu:
    SongSelector.Show()
    
    KeyWait('space','D')
    SongSelector.Hide()
    WinActivate('WEBFISHING v1.08')
    Main(Dropdown.Value)
    
    goto ShowMenu
}

; these coordinates need to be changed to be relative to the
; window dimensions. Also the game can handle the clicks
; at lightning speed so the input sendmode is used
UpdateString(String,Finger)
{
    Sendmode 'Input'
    X := 260 + String * 27
    Y := 90 + Finger * 50
    Click X, Y
}

Main(Song)
{
    tabs := midiToEventArray('midi\' SongList[Song])
    tabs := eventArraytoTabs(tabs, tabs[1])

    ; sets all strings to fret 0 then clears them to avoid
    ; potentially unwanted notes
    Click 455, 80
    loop 6
    {
        UpdateString(A_Index,0)
    }

    ; this doesn't need to be here exactly, but 30 ms delay is a good balance;
    ; between too much delay between simultaneous notes and dropped inputs
    SetKeyDelay -1, 30

    KeysReference := ['q','w','e','r','t','y']

    Lasts := ['','','','','','']

    ; the tabs array arrives to this loop looking like this:
    ; [
    ; <tempo in bpm>,
    ; [<fret>,<fret>,<fret>,<fret>,<fret>,<fret>,<dT in beats>],
    ; [etc,etc],
    ; <tempo change if any>,
    ; ]

    for chord in tabs
    {
        ; hold L while playing to stop the music
        if NOT KeyWait('l', 'T0.001')
        {
            break
        }

        ; tempo changes are stored in tabs as single values
        if IsNumber(chord)
        {
            tempo := chord
            continue
        }

        ; we will concatenate the necessary qwerty keys into this string to strum the
        ; desired strings for each chord
        PlayKeys := ''

        ; epic coding
        for n in [1,2,3,4,5,6]
        {
            if isInteger(chord[n]) AND chord[n] != Lasts[n]
            {
                UpdateString(n, chord[n])
                Lasts[n] := chord[n]
            }
            if isInteger(chord[n])
            {
                PlayKeys .= KeysReference[n]
            }
        }

        ; sendmode event as determined through trial and error
        Sendmode 'Event'
        Send PlayKeys

        ; in a just and perfect world this should be multiplied by 30 not 25 but anyway
        ; this accounts for the dT between chords
        Sleep (chord[7]*60000/tempo)-StrLen(PlayKeys)*25
    }
}

midiToEventArray(filename)
{
    MidiFile := FileOpen(filename,0)
    
    MidiFile.RawRead(header := Buffer(4))
    MidiFile.RawRead(headerLength := Buffer(4))
    MidiFile.RawRead(formatType := Buffer(2))
    MidiFile.RawRead(numTracks := Buffer(2))
    MidiFile.RawRead(timeDivision := Buffer(2))

    header := StrGet(header,,'CP0')
    headerLength := BSNumGet(headerLength, 'UInt')
    formatType := BSNumGet(formatType, 'UShort')
    numTracks := BSNumGet(numTracks, 'UShort')
    timeDivision := BSNumGet(timeDivision, 'UShort')
    

    eventArray := []
    eventArray.InsertAt(0,timeDivision)

    while MidiFile.Pos < Midifile.Length {
        ;Read chunk parameters
        MidiFile.Pos += 4
        MidiFile.RawRead(chunkLength := Buffer(4))
        chunkLength := BSNumGet(chunkLength, 'UInt')

        lastStatus := 0x00

        ;step into chunk
        while A_Index < chunkLength {

            debugMessage := ''

            deltaTime := parse_var_length(MidiFile)

            MidiFile.RawRead(eventByte := Buffer(1))
            eventByte := NumGet(eventByte, 'UChar')

            ; we only care about meta events if they change the tempo
            ; or have a nonzero dT. It's possible I'm missing some edge case event types
            ; here, there seem to be more than are documented in any one place
            if eventByte = 0xFF { ; Meta events
                MidiFile.RawRead(metaType := Buffer(1))
                metaType := NumGet(metaType, 'UChar')

                if metaType = 0x51 {
                    MidiFile.Pos += 1
                    MidiFile.RawRead(tempoChange := Buffer(3))
                    tempoChange := BSNumGet(tempoChange, "UWide")
                    eventArray.InsertAt(0,tempoChange)
                    debugMessage := '`ntempo change in position ' . String(eventArray.Length) . ' from ' . String(MidiFile.Pos-1)
                }
                else if metaType = 0x2F {
                    MidiFile.Pos += 1
                    break
                }
                else {
                    length := parse_var_length(MidiFile)
                    MidiFile.Pos += length
                    debugMessage := '`nmeta event skipped ' . String(eventArray.Length) . ' from ' . String(MidiFile.Pos-1)
                }
                
                if deltaTime != 0 {
                    eventArray.InsertAt(0,[0,deltaTime])
                    debugMessage := '`ntimed meta event in position ' . String(eventArray.Length) . ' from ' . String(MidiFile.Pos-1)
                }
            }
            ;sysex shmysex who cares
            else If eventByte = 0xF0 or eventByte = 0xF7 {
                length := parse_var_length(MidiFile)
                MidiFile.Pos += length
                
                if deltaTime != 0 {
                    eventArray.InsertAt(0,[0,deltaTime])
                    debugMessage := '`ntimed sysex event in position ' . String(eventArray.Length) . ' from ' . String(MidiFile.Pos-1)
                }
            }
            else {
                status:
                if 0x90 <= eventByte AND eventByte <= 0x9F {
                    lastStatus := eventByte
                    MidiFile.RawRead(note := Buffer(1))
                    note := NumGet(note,'UChar')
                    MidiFile.RawRead(velocity := Buffer(1))
                    velocity := NumGet(velocity, 'UChar')

                    ; Some notes have noteoff events as 0-velocity noteons. There are two categories of such events: 'encapsulations', and '0dT'
                    ; encapsulations have a nonzero dT. 0dTs should be prevented from being written at all, while encapsulations should search
                    ; backward through the array and remove their counterpart.
                    if velocity = 0 AND deltaTime = 0{
                        debugMessage := '`n0dt 0velocity noteon rejected from position ' . String(eventArray.Length) . ' from ' . String(MidiFile.Pos-1)
                    }
                    else if velocity = 0 AND deltaTime != 0 {
                        while true{
                            if eventArray[eventArray.Length+1-A_Index][1] = note {
                                eventArray.RemoveAt(eventArray.Length+1-A_Index)
                                eventArray.InsertAt(0,[note,deltaTime])
                                debugMessage := '`n0velocity noteon from ' . String(MidiFile.Pos-1) . ', corrected position ' . String(eventArray.Length+1-A_Index)
                                break
                            }
                        }
                    }
                    else {
                        eventArray.InsertAt(0,[note,deltaTime])
                        debugMessage := '`nnote on ' . String(note) . ' in position ' . String(eventArray.Length) . ' from ' . String(MidiFile.Pos-1)
                    }
                        

                }
                else if 0x80 <= eventByte AND eventByte <= 0x8F {
                    lastStatus := eventByte
                    MidiFile.Pos += 2
                    if deltaTime != 0
                        eventArray.InsertAt(0,[0,deltaTime])
                }
                else if 0xA0 <= eventByte AND eventByte <= 0xBF {
                    lastStatus := eventByte
                    MidiFile.Pos += 2
                    if deltaTime != 0
                        eventArray.InsertAt(0,[0,deltaTime])
                }
                else if 0xC0 <= eventByte AND eventByte <= 0xDF {
                    lastStatus := eventByte
                    MidiFile.Pos += 1
                    if deltaTime != 0
                        eventArray.InsertAt(0,[0,deltaTime])
                }
                else if 0xE0 <= eventByte AND eventByte <= 0xEF {
                    lastStatus := eventByte
                    MidiFile.Pos += 2
                    if deltaTime != 0
                        eventArray.InsertAt(0,[0,deltaTime])
                }
                else{
                    eventByte := lastStatus
                    MidiFile.Pos -= 1
                    goto status
                }
            }
            OutputDebug(debugMessage)
        }
    }
    return eventArray
}

eventArraytoTabs(array,timeDivision)
{
    array.RemoveAt(1)
    openStrings := [40,45,50,55,59,64]
    tabs := []
    toSort := ''
    sortedArray := []
    currentChord := ['','','','','','',0]
    for event in array {
        if IsInteger(event) {
            event := 60000000/event
            tabs.InsertAt(0,event)
        }
        else if event[2] = 0 {
            toSort .= String(event[1]) . ','
        }
        else if event[2] = 1{
            continue
        }
        else {
            toSort .= String(event[1])
            currentChord[7] := event[2]/timeDivision
            toSort := Sort(toSort,'N D, R')
            loop parse toSort, ','
                sortedArray.InsertAt(0,Number(A_LoopField))
            
            for note in sortedArray {
                if note < 40 OR note > 79
                    continue
                loop 6 {
                    openStr := openStrings[7-A_Index]
                    fret := note - openStr
                    if note >= openStr AND currentChord[7-A_Index] = '' AND fret <= 15 {
                        currentChord[7-A_Index] := fret
                        break
                    }
                }
            }
            tabs.InsertAt(0,currentChord)
            toSort := ''
            sortedArray := []
            currentChord := ['','','','','','',0]
            
        }

    }
    return tabs
}

; im actually kinda proud of the UWide byteswap I felt really clever using a bitshift
; also can we talk about how stupid it is that ahk doesn't have a better
; way of dealing with endianness
; ...says the girl who is obstinately writing code in fricking autohotkey
BSNumGet(num, type)
{
    if type = 'UInt' {
        num := NumGet(num, 'UInt')
        num := DllCall("msvcr100\_byteswap_ulong", 'UInt', num, 'UInt')
    }
    else if type = 'UChar'{
        num := DllCall("msvcr100\_byteswap_uint8", "UChar", NumGet(num, type), "UChar")
    }
    else if type = 'UWide'{
        num.Size += 1
        num := NumGet(num,'UInt')
        num := DllCall("msvcr100\_byteswap_ulong", 'UInt', num, 'UInt')
        num >>= 8
        
        
    }
    else
        num := DllCall("msvcr100\_byteswap_" . Format('{:L}',type), type, NumGet(num,Type), type)
    return num
}

; I genuinely do not understand how this part of the code works I'm just trusting the magic
parse_var_length(data)
{
    value := 0
    temp := true
    while temp
    {
        data.RawRead(byte := Buffer(1))
        byte := NumGet(byte,'UChar')
        value := (value << 7) | (byte & 0x7F)
        if NOT (byte & 0x80)
            temp := false
    }
    return value

}

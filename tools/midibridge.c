/* midibridge -- CoreMIDI to raw MIDI bytes, for feeding Hatari's --midi-in.
 *
 * macOS has no /dev/midi node for Hatari to open, so we pull bytes off
 * CoreMIDI and push them into a FIFO that Hatari reads instead.
 *
 *   mkfifo /tmp/noiseav.midi
 *   tools/midibridge -o /tmp/noiseav.midi
 *
 * The FIFO is opened O_RDWR on purpose: that never blocks waiting for a
 * reader, and the pipe never reports EOF, so Hatari can be started and
 * restarted underneath us without the bridge noticing.
 */
#include <CoreMIDI/CoreMIDI.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

static int   out_fd        = STDOUT_FILENO;
static int   keep_sensing  = 0;
static int   verbose       = 0;
static char  want[128]     = "";      /* substring of the source name, or "" for all */

#define MAX_SRC 64
static MIDIEndpointRef connected[MAX_SRC];
static int             n_connected = 0;
static MIDIPortRef     port;

static void name_of(MIDIEndpointRef ep, char *buf, size_t n)
{
    CFStringRef s = NULL;
    buf[0] = '\0';
    if (MIDIObjectGetStringProperty(ep, kMIDIPropertyDisplayName, &s) == noErr && s) {
        CFStringGetCString(s, buf, (CFIndex)n, kCFStringEncodingUTF8);
        CFRelease(s);
    }
}

static void emit(const Byte *d, int n)
{
    if (keep_sensing) { (void)!write(out_fd, d, (size_t)n); return; }
    /* Active sensing (FE) is pure keepalive chatter and costs a BIOS trap
     * per byte on the ST, so drop it unless asked to keep it. */
    Byte tmp[512];
    int  k = 0;
    for (int i = 0; i < n && k < (int)sizeof tmp; i++)
        if (d[i] != 0xFE) tmp[k++] = d[i];
    if (k) (void)!write(out_fd, tmp, (size_t)k);
}

static void readProc(const MIDIPacketList *pkts, void *a, void *b)
{
    (void)a; (void)b;
    const MIDIPacket *p = &pkts->packet[0];
    for (unsigned i = 0; i < pkts->numPackets; i++) {
        emit(p->data, p->length);
        if (verbose) {
            fprintf(stderr, "<-");
            for (unsigned j = 0; j < p->length; j++) fprintf(stderr, " %02X", p->data[j]);
            fprintf(stderr, "\n");
        }
        p = MIDIPacketNext(p);
    }
}

static int already(MIDIEndpointRef ep)
{
    for (int i = 0; i < n_connected; i++) if (connected[i] == ep) return 1;
    return 0;
}

static void connect_sources(void)
{
    ItemCount n = MIDIGetNumberOfSources();
    for (ItemCount i = 0; i < n; i++) {
        MIDIEndpointRef ep = MIDIGetSource(i);
        if (!ep || already(ep)) continue;
        char nm[128]; name_of(ep, nm, sizeof nm);
        if (want[0] && !strstr(nm, want)) continue;
        if (MIDIPortConnectSource(port, ep, NULL) == noErr && n_connected < MAX_SRC) {
            connected[n_connected++] = ep;
            fprintf(stderr, "connected: %s\n", nm);
        }
    }
    if (!n_connected) fprintf(stderr, "no MIDI sources yet -- plug the keyboard in, "
                                      "it will connect by itself\n");
}

static void notifyProc(const MIDINotification *msg, void *ctx)
{
    (void)ctx;
    if (msg->messageID == kMIDIMsgSetupChanged) connect_sources();
}

int main(int argc, char **argv)
{
    const char *outpath = NULL;
    int list_only = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-o") && i + 1 < argc)      outpath = argv[++i];
        else if (!strcmp(argv[i], "-s") && i + 1 < argc) snprintf(want, sizeof want, "%s", argv[++i]);
        else if (!strcmp(argv[i], "-l"))                 list_only = 1;
        else if (!strcmp(argv[i], "-v"))                 verbose = 1;
        else if (!strcmp(argv[i], "--keep-sensing"))     keep_sensing = 1;
        else {
            fprintf(stderr,
              "usage: %s [-o fifo] [-s name-substring] [-l] [-v] [--keep-sensing]\n"
              "  -o  write raw MIDI here (default stdout); a FIFO is the point\n"
              "  -s  only connect sources whose name contains this\n"
              "  -l  list sources and exit\n"
              "  -v  echo bytes to stderr\n", argv[0]);
            return 2;
        }
    }

    if (list_only) {
        ItemCount n = MIDIGetNumberOfSources();
        fprintf(stderr, "%lu MIDI source(s):\n", (unsigned long)n);
        for (ItemCount i = 0; i < n; i++) {
            char nm[128]; name_of(MIDIGetSource(i), nm, sizeof nm);
            fprintf(stderr, "  [%lu] %s\n", (unsigned long)i, nm);
        }
        return 0;
    }

    if (outpath) {
        out_fd = open(outpath, O_RDWR | O_CREAT, 0644);
        if (out_fd < 0) { perror(outpath); return 1; }
    }

    MIDIClientRef client;
    if (MIDIClientCreate(CFSTR("noiseav-bridge"), notifyProc, NULL, &client) != noErr) {
        fprintf(stderr, "MIDIClientCreate failed\n"); return 1;
    }
    if (MIDIInputPortCreate(client, CFSTR("in"), readProc, NULL, &port) != noErr) {
        fprintf(stderr, "MIDIInputPortCreate failed\n"); return 1;
    }
    connect_sources();
    fprintf(stderr, "bridging to %s -- ctrl-C to stop\n", outpath ? outpath : "stdout");
    CFRunLoopRun();
    return 0;
}

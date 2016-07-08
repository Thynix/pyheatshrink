cimport cython
from cpython cimport array
import array
from cpython.mem cimport PyMem_Malloc, PyMem_Free
from libc.stdint cimport uint8_t

cimport cheatshrink

DEFAULT_WINDOW_SZ2 = 11
DEFAULT_LOOKAHEAD_SZ2 = 4


cdef class Encoder:
    cdef cheatshrink.heatshrink_encoder *_hse

    def __cinit__(self, **kwargs):
        self._hse = cheatshrink.heatshrink_encoder_alloc(
            kwargs.get('window_sz2', DEFAULT_WINDOW_SZ2),
            kwargs.get('lookahead_sz2', DEFAULT_LOOKAHEAD_SZ2))
        if self._hse is NULL:
            raise MemoryError()

    def __dealloc__(self):
        if self._hse is not NULL:
            cheatshrink.heatshrink_encoder_free(self._hse)

    @property
    def max_output_size(self):
        """The maximum allowed size of the output buffer."""
        return 1 << self._hse.window_sz2

    cdef size_t sink(self, array.array in_buf):
        """
        Sink up to `size` bytes in to the encoder.
        """
        cdef size_t input_size
        res = cheatshrink.heatshrink_encoder_sink(
            self._hse, <uint8_t *>in_buf.data.as_voidptr,
            <size_t>len(in_buf), &input_size)
        if res < 0:
            raise RuntimeError("Encoder sink failed.")
        return input_size

    cdef poll(self):
        """
        Poll the output from the encoder.
        This should return an array of bytes.
        """
        cdef size_t poll_size

        cdef array.array out_buf = array.array('B', [])
        # Resize to a decent length
        array.resize(out_buf, self.max_output_size)

        res = cheatshrink.heatshrink_encoder_poll(
            self._hse, <uint8_t *>out_buf.data.as_voidptr,
            self.max_output_size, &poll_size)
        if res < 0:
            raise RuntimeError("Encoder poll failed.")

        # Resize to drop unused elements
        array.resize(out_buf, poll_size)

        # TODO: For the love of god get rid of me
        done = res == cheatshrink.HSER_POLL_EMPTY
        return (out_buf, done)

    cdef finish(self):
        """
        Notify the encoder that the input stream is finished.
        """
        res = cheatshrink.heatshrink_encoder_finish(self._hse)
        if res < 0:
            raise RuntimeError("Encoder finish failed.")
        return res == cheatshrink.HSER_FINISH_DONE


def encode(buf, window_sz2=11, lookahead_sz2=4):
    encoder = Encoder()

    cdef array.array byte_buf = array.array('B', buf)

    cdef int total_sunk_size = 0
    cdef array.array encoded = array.array('B', [])

    while True:
        if total_sunk_size < len(byte_buf):
            total_sunk_size += encoder.sink(byte_buf)

        while True:
            polled, done = encoder.poll()
            array.extend(encoded, polled)
            if done:
                break

        if total_sunk_size >= len(byte_buf):
            if encoder.finish():
                break

    return encoded


def decode(buf, window_sz2=11, lookahead_sz2=4):
    pass

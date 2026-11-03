# ``HardwareClock/HardwareClock``

## Topics

### Creating a clock

- ``isAvailable``
- ``calibrate()``
- ``init(frequency:)``
- ``frequency``

### Reading the clock

- ``now``
- ``minimumResolution``
- ``sleep(until:tolerance:)``

### Raw counter reads

- ``readCounter()``
- ``Reading``

### Converting ticks

- ``nanoseconds(fromTicks:)``
- ``elapsedNanoseconds(sinceTicks:)``
- ``elapsedNanoseconds(since:)``

### Instants

- ``Instant``

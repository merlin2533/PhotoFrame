/**
 * Minimal counting semaphore for bounding concurrent async work (e.g. image
 * decode/re-encode). `acquire()` resolves with a release function; callers
 * must call it exactly once, normally in a `finally` block. Extra calls
 * queue in FIFO order until a slot frees up.
 */
export class Semaphore {
  private active = 0;
  private readonly waiting: Array<() => void> = [];

  constructor(private readonly max: number) {
    if (!Number.isInteger(max) || max < 1) {
      throw new Error('Semaphore max must be a positive integer');
    }
  }

  acquire(): Promise<() => void> {
    return new Promise((resolve) => {
      const grant = () => {
        this.active += 1;
        let released = false;
        resolve(() => {
          if (released) return;
          released = true;
          this.active -= 1;
          this.waiting.shift()?.();
        });
      };

      if (this.active < this.max) {
        grant();
      } else {
        this.waiting.push(grant);
      }
    });
  }
}

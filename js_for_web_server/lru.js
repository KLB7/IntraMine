// From https://stackoverflow.com/questions/996505/lru-cache-implementation-in-javascript
// with minor changes.
// Strictly speaking this is a "most recently used" cache, intended
// for putting the most recently added item at the front of the list.
// See glosser.js for an example.

class LRUCache {
    constructor(max = 10) {
        this.max = max;
        this.cache = new Map();
    }

    get(key) {
        let item = this.cache.get(key);
        if (item) {
            // refresh key
            this.cache.delete(key);
            this.cache.set(key, item);
        }
        return item;
    }

    set(key, val) {
        // refresh key
        if (this.cache.has(key)) this.cache.delete(key);
        // evict oldest
        else if (this.cache.size == this.max)
            {
            const lastKey = Array.from(this.cache.keys()).pop();
            this.cache.delete(lastKey); 
            }
        
         const existingEntries = [...this.cache.entries()];
        this.cache.clear();
        this.cache.set(key, val);
        for (const [key, val] of existingEntries)
            {
            this.cache.set(key, val);
            }
    }
}

// lru.js: from https://progressivecoder.com/lru-cache-implementation-using-javascript-linked-list-and-objects/
// A Least Recently Used cache.

class Node {
    constructor(key, value) {
        this.key = key;
        this.value = value;
        this.next = null;
        this.prev = null;
    }
}

class LRUCache {
    constructor() {
        this.head = null;
        this.tail = null;
        this.size = 0;
        this.maxSize = 4;
        this.cache = {};
    }

    put(key, value) {
        let newNode

        // if the key not present in cache
        if (this.cache[key] === undefined) newNode = new Node(key, value);

        //if we have an empty list
        if(this.size === 0) {
            this.head = newNode;
            this.tail = newNode;
            this.size++;
            this.cache[key] = newNode;
            return this;
        }

        if (this.size === this.maxSize) {
            //remove from cache
            delete this.cache[this.tail.key]

            //set new tail
            this.tail = this.tail.prev;
            this.tail.next = null;
            this.size--;
        }

        //add an item to the head
        this.head.prev = newNode;
        newNode.next = this.head;
        this.head = newNode;
        this.size++;
    
        //add to cache
        this.cache[key] = newNode; 
        return this;
        
    }

    get(key) {
        if (!this.cache[key]){
            return undefined
        }

        let foundNode = this.cache[key];
        
        if(foundNode === this.head) return foundNode;

        let previous = foundNode.prev;
        let next = foundNode.next;

        if (foundNode === this.tail){
            previous.next = null;
            this.tail = previous;
        }else{
            previous.next = next;
            next.prev = previous;
        }

        this.head.prev = foundNode;
        foundNode.next = this.head;
        foundNode.prev = null;
        this.head = foundNode;

        return foundNode;      
    }
}

// let cache = new LRUCache();
// cache.put(1, 'A');
// cache.put(2, 'B');
// cache.put(3, 'C');
// cache.put(4, 'D');

// cache.get(2);
// cache.get(1);

// cache.put(5, 'E');
// cache.put(6, 'F');

// cache.get(1);
// cache.get(8);

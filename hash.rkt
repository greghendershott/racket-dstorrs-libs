#lang racket

(require racket/hash ; for hash-union
         )
(provide (all-defined-out))

;; *) hash->keyword-apply : take a function and a hash.  Assume the
;;     keys of the hash are keyword arguments and call appropriately.

;; *) hash-key-exists? : alias for hash-has-key? because I always forget the name
;; *) hash-keys->strings : take a hash where keys are symbols or strings, make them strings
;; *) hash-keys->symbols : take a hash where keys are symbols or strings, make them symbols
;; *) hash->immutable : convert an (im)mutable hash to an immutable one
;; *) hash->meld   : combine to or more hashes with later entries overwriting earlier ones
;; *) hash->mutable   : convert an (im)mutable hash to a mutable one
;; *) hash-rename-key : change, e.g., key 'name to be 'first-name
;; *) hash-slice      : takes a hash and a list of keys, returns the matching values
;; *) mutable-hash    : creates a mutable hash using the convenient syntax of (hash)
;; *) safe-hash-remove : does hash-remove or hash-remove! as needed.  Returns the hash.
;; *) safe-hash-set : does hash-set or hash-set! as needed. Returns the hash.

(define hash-key-exists? hash-has-key?) ; just as alias because I always forget the name


;;----------------------------------------------------------------------

(define/contract (hash-keys->strings h #:dash->underscore? [dash->underscore? #f])
  (->* (hash?) (#:dash->underscore? boolean?) hash?)

  (define (to-string x)
    (cond ((list?   x)   (apply string-append (map to-string x)))
          ((vector?   x) (to-string (vector->list x)))
          (else (~a x))))

  ((if (immutable? h) identity hash->mutable)
   (for/hash ([(k v) h])
     (let ([key (to-string k)])
       (values (if dash->underscore? (regexp-replace* #px"-" key "_") key)
               v)))))

;;----------------------------------------------------------------------

(define/contract (hash-keys->symbols h)
  (-> hash? hash?)
  ((if (immutable? h) identity hash->mutable)
   (for/hash ([(k v) h])
     (values (if (symbol? k) k (string->symbol (~a k)))
             v))))

;;----------------------------------------------------------------------

(define (hash->immutable h)
  (if (immutable? h)
      h
      (apply hash (flatten (for/list ((k (hash-keys h)))
                             (cons k (hash-ref h k)))))))

;;----------------------------------------------------------------------

(define/contract (sorted-hash-keys hsh [func symbol<?])
  (->* (hash?) ((unconstrained-domain-> boolean?)) list?)
  (sort (hash-keys hsh) func))

;;----------------------------------------------------------------------

(define/contract (hash->mutable h)
  (-> hash? (and/c hash? (not/c immutable?)))
  (if (not (immutable? h))
      h
      (make-hash (for/list ((k (hash-keys h)))
                   (cons k (hash-ref h k))))))

;;----------------------------------------------------------------------

(define (mutable-hash . args)
  (hash->mutable (apply hash args)))

;;----------------------------------------------------------------------

(define/contract (mutable-hash? data)
  (-> hash? boolean?)
  (not (immutable? data)))

;;----------------------------------------------------------------------

(define/contract (hash-meld . hshs)
  (->* () () #:rest (non-empty-listof hash?) hash?)
  (cond [(= (length hshs) 1) (first hshs)]
        [else
         (define first-hsh (first hshs))
         (define is-immut? (immutable? first-hsh))
         ((if is-immut? identity hash->mutable)
          (apply hash-union
                 (map hash->immutable hshs)
                 #:combine (lambda (x y) y)))]))

;;----------------------------------------------------------------------

(define/contract (hash-slice the-hash keys)
  (-> hash? list? list?)
  (for/list ((k keys))
    (hash-ref the-hash k)))

;;----------------------------------------------------------------------

;; (define/contract (safe-hash-remove h #:key-is-list [key-is-list? #f] . keys)
;;    (->* (hash?) (#:key-is-list boolean?) #:rest (listof any/c) hash?)
;;
;; Mutable hashes use hash-remove! which returns (void).  Immutable
;; hashes use hash-remove and return the hash. Both will throw if you
;; use the wrong 'remove' function.  Both functions only remove a
;; single key at a time.  If you'd like to not deal with any of this,
;; use safe-hash-remove: it works on both mutable and immutable
;; hashes, it always returns the hash, and it removes as many keys as
;; you like, all in one go.
;;
;; Examples:
;;
;;    ;    Here's a hash that includes a bunch of data that should be
;;    ;    shown to the user and also a bunch of metadata needed by the
;;    ;    application for other purposes:
;;    (define application-h (hash 'food? #t 'type 'fruit 'id 7 'added-to-db-at 1516997724))
;;
;;    ;    Let's get it ready for output by stripping out the metadata
;;    (define output-h (safe-hash-remove h 'id 'added-to-db-at)) => only has 'food? and 'type keys
;;
;;    ;    Same as above, but the keys are passed as a list -- perhaps
;;    ;    they were generated by a DB query, or a map and it's a bother to
;;    ;    unwrap them.
;;    (define output-h (safe-hash-remove h '(id added-to-db-at))) => only 'food? and 'type remain
;;
;;    ;    Note that you can freely mix passing some keys explicitly and some as a list
;;    (define output-h (safe-hash-remove h '(id) 'added-to-db-at)) => same as above
;;
;;    ;    Edge case: There is a key in your hash that really is a list.
;;    ;    This is a problem, since the keys list that you pass in will be
;;    ;    flattened, so the key that is a list will be missed.
;;    (define weird-h   (hash '(foo bar) 'x 'a 7 'b 8)) ; the first key is a list
;;
;;    ;    Use #:key-is-list to avoid flattening
;;    WRONG: (safe-hash-remove weird-h '(foo bar)))                     ; hash unchanged
;;    WRONG: (safe-hash-remove weird-h '(foo bar) 'a))                  ; only 'a removed
;;    RIGHT: (safe-hash-remove weird-h '(foo bar) 'a #:key-is-list #t)) ; both removed
;;    RIGHT: (safe-hash-remove weird-h '((foo bar) 'a)))                ; both removed
;;
(define/contract (safe-hash-remove h #:key-is-list [key-is-list? #f] . keys)
  (->* (hash?) (#:key-is-list boolean?) #:rest (listof any/c) hash?)
  (define is-imm (immutable? h))
  (define keys-list
    (cond [key-is-list? keys] ; very unlikely, but included for completeness
          [(null? keys) keys]
          [(> (length keys) 1) keys]
          [(list? (car keys)) (car keys)]
          [else keys]))

  (for/fold ((hsh h))
            ((k keys-list))
    (if is-imm
        (hash-remove hsh k)
        (begin (hash-remove! hsh k) h))))

;;----------------------------------------------------------------------

(define/contract (safe-hash-set h  . args)
  (->* (hash?)
       ()
       #:rest (and/c list?
                     (lambda (lst)
                       (let ([len (length lst)])
                         (and (even? len)
                              (not (= 0 len))))))
       hash?)

  (define args-hash (apply hash args))
  (define is-imm (immutable? h))
  (for/fold ((hsh h))
            ((k (hash-keys args-hash)))
    (if is-imm
        (hash-set hsh k (hash-ref args-hash k))
        (begin (hash-set! hsh k (hash-ref args-hash k)) h))))

;;----------------------------------------------------------------------

(define/contract (hash-rename-key h old-key new-key)
  (-> hash? any/c any/c hash?)

  (when (not (hash-has-key? h old-key))
    (raise-arguments-error 'hash-rename-key
                           "no such key"
                           "old-key" old-key
                           "new-key" new-key
                           "hash" h))

  (when (hash-has-key? h new-key)
    (raise-arguments-error 'hash-rename-key
                           "destination key exists"
                           "old-key" old-key
                           "new-key" new-key
                           "hash" h))

  (safe-hash-remove
   (safe-hash-set h new-key (hash-ref h old-key))
   old-key))

;;----------------------------------------------------------------------

;; (define/contract (hash-remap h
;;                              #:remove    [remove-keys '()]
;;                              #:overwrite [overwrite   #f ]
;;                              #:add       [add         #f ]
;;                              #:rename    [remap       #f ]
;;                              )
;;   (->* (hash?) (#:rename hash? #:add hash? #:overwrite hash? #:remove list?) hash?)
;;
;;  Key mnemonic:  ROARen. Remove. Overwrite. Add. Rename.
;;
;;    This will munge hashes any way you like.  You can rename keys,
;;    remove keys, overwrite the value of keys, and add new keys.  The
;;    order of application is: remove -> overwrite -> add -> rename
;;
;;    The return value generally won't be eq? to the input, but it is
;;    guaranteed to be of the same type (mutable / immutable)
;;
;;    FIRST: remove any values we were told to remove via the #:remove list
;;        (hash-remap h #:remove '(key1 key2))
;;
;;    SECOND: overwrite any values from the original hash that we were
;;    told to overwrite via the #:overwrite hash.  If the new value is
;;    a procedure then it will be invoked and its result will be the
;;    new value.  The procedure must have the signature:
;;
;;        (-> hash? any/c any/c any/c)  ; takes a hash, key, orig-val.  Returns one value
;;
;;    The arguments will be: the hash we're updating, the key
;;    we're updating, and the original value.  It must return a
;;    single value.
;;
;;    If you actually want to pass in a procedure (e.g. if you're
;;    building a jumptable) then you'll have to wrap it like so:
;;
;;        (lambda (hsh key val orig-val)  ; the 'generate a value' procedure
;;            (lambda ...))               ; the procedure it generates
;;
;;    THIRD: add any additional keys that we were told to add.
;;    NOTE: This will throw an exception if you try to add a key
;;    that is already there.
;;
;;    FOURTH: rename keys
;;
;; (define h (hash 'group 'fruit   'color 'red    'type 'apple))
;;
;; (hash-remap h #:add (hash 'subtype 'honeycrisp))
;;    => (hash 'group 'fruit 'color 'red 'type 'apple 'subtype 'honeycrisp))
;;
;;    ; It's not legal to add a key that is already there.  If you want to do that, use #:overwrite
;; (hash-remap h #:add (hash 'group 'tasty))
;;    => EXCEPTION
;;
;; (hash-remap h #:remove '(group color)
;;    => (hash 'type 'apple)
;;
;; (hash-remap h #:rename (hash 'color 'shade  'type 'species )
;;    => (hash 'group 'fruit    'shade 'red    'species 'apple)
;;
;; (hash-remap h #:overwrite (hash 'group 'tasty   'color 'green   'type 'granny-smith))
;;    => (hash 'group 'tasty    'color 'green    'type 'granny-smith)
;;
;;    ; Alternatively, have the new value generated
;; (hash-remap (hash 'x 7 'y 9) #:overwrite (hash 'x (lambda (h k v) (add1 v))))
;;    =>       (hash 'x 8 'y 9)
;;
;; (hash-remap h  #:add       (hash 'vendor 'bob)
;;                #:overwrite (hash 'color 'green   'type 'granny-smith)
;;                #:remove    '(group)
;;                #:rename    (hash 'vendor 'seller))
;;    => (hash 'color 'green    'type 'granny-smith    'seller 'bob))
(define/contract (hash-remap h
                             #:rename    [remap #f]
                             #:remove    [remove-keys #f]
                             #:overwrite [overwrite #f]
                             #:add       [add #f]
                             )
  (->* (hash?) (#:rename hash? #:add hash? #:overwrite hash? #:remove list?) hash?)

  (let/ec return
    ; Just return unless we are going to rename, remove, overwrite, or
    ; add someting.
    (when (not (ormap (negate false?) (list remap remove-keys overwrite add)))
      (return h))

    ; Okay, we're going to make some sort of change
    (define h-is-immutable? (immutable? h))

    (define union-func (if h-is-immutable? hash-union hash-union!))

    (define (default-hash) (if h-is-immutable? (hash) (make-hash)))
    (define overwrite-hash (or overwrite (default-hash)))
    (define add-hash       (or add       (default-hash)))
    (define remap-hash     (or remap     (default-hash)))

    ;; (say "original hash: " h
    ;;      "\n\t immutable?     " (immutable? h)
    ;;      "\n\t overwrite:     " overwrite-hash
    ;;      "\n\t add:           " add-hash
    ;;      "\n\t remap-hash:    " remap-hash)

    ;;    First, remove any values we were told to remove,
    (define base-hash
      (apply (curry safe-hash-remove h) (or remove-keys '())))

    ;;(say "hash after remove: " base-hash)

    ;;    Now, overwrite any values from the original hash that we
    ;;    were told to overwrite.  If the new value is a procedure
    ;;    then it will be invoked and its result will be the new
    ;;    value.  The procedure must have the signature:
    ;;
    ;;        (-> hash? any/c any/c any/c)  ; hash, key, orig-val, return one value
    ;;
    ;;    The arguments will be: the hash we're updating, the key
    ;;    we're updating, and the original value.  It must return a
    ;;    single value.
    ;;
    ;;    If you actually want to pass in a procedure (e.g. if you're
    ;;    building a jumptable) then you'll have to wrap it like so:
    ;;
    ;;        (lambda (hsh key val orig-val)  ; the 'generate a value' procedure
    ;;            (lambda ...))               ; the procedure it generates
    ;;
    ;;  NB: hash-union! modifies its target in place and then returns
    ;;  #<void>, because of course it does.  As a result, we need to
    ;;  check whether we're dealing with an immutable hash in order to
    ;;  know what to return.
    (define overwritten-hash
      (let ([hsh (union-func base-hash
                             overwrite-hash
                             #:combine/key (lambda (key orig-val overwrite-val)
                                             ;(say "entering combiner with args: " (string-join (map ~v (list key orig-val overwrite-val)) "; "))
                                             (cond [(procedure? overwrite-val)
                                                    ;(say "proc: " overwrite-val)
                                                    (overwrite-val base-hash key orig-val)]
                                                   [else overwrite-val])))])
        ;(say "finished overwrite")
        (if (void?  hsh) base-hash hsh))) ; void if we're dealing with mutable hash

    ;(say "hash with overwrites: " overwritten-hash)

    ;;    Next, add any additional keys that we were told to add.
    ;;
    ;;    NOTE: This will throw an exception if you try to add a key
    ;;    that is already there.
    (define hash-with-adds
      (let ([hsh (union-func overwritten-hash
                             add-hash
                             #:combine/key (lambda _ (raise-arguments-error
                                                      'hash-remap
                                                      "add-hash cannot include keys that are in base-hash"
                                                      "add-hash" add-hash
                                                      "hash to add (remove and overwrite already done)" overwritten-hash)))])
        (if (void? hsh) overwritten-hash hsh))) ; it's void when using mutable hash

    ;(say "hash-with-adds is: " hash-with-adds)
    ;(say "about to rename")
    ;;    Finally, rename keys
    (for/fold ([h hash-with-adds])
              ([(key val) remap-hash])
      ;(say "renaming in hash with key/val: " h "," key "," val)
      (hash-rename-key h key val))))

;;----------------------------------------------------------------------


(define/contract (hash->keyword-apply func hsh [positionals '()])
  (->* (procedure? (hash/c symbol? any/c)) (list?) any)

  (define keys (sort (hash-keys hsh) symbol<?))

  (keyword-apply func
                 (map (compose string->keyword symbol->string) keys)
                 (map (curry hash-ref hsh) keys)
                 positionals))

;;----------------------------------------------------------------------

;; StacksConnect: Bitcoin-Native Social Network
;; A decentralized social platform built for the Bitcoin ecosystem
;;
;; Summary:
;; StacksConnect leverages Stacks Layer 2 to create a censorship-resistant social network
;; where users maintain sovereign control over their data, relationships, and digital identity.
;; Built on Bitcoin's security foundation with smart contract functionality.
;;
;; Description:
;; This contract implements a comprehensive social networking protocol featuring:
;; - Sovereign user identity and profile management
;; - Decentralized friendship and blocking systems  
;; - Privacy-first architecture with granular controls
;; - Rate limiting and spam protection mechanisms
;; - Batch processing for scalability optimization
;; - Bitcoin-aligned values of self-custody and censorship resistance
;;
;; The platform empowers users to build meaningful connections while maintaining
;; full ownership of their social graph and personal data, secured by Bitcoin's
;; immutable ledger through Stacks smart contracts.

;; ERROR CONSTANTS - Standardized Error Handling System

(define-constant ERR_NOT_FOUND (err u100))
(define-constant ERR_ALREADY_EXISTS (err u101))
(define-constant ERR_UNAUTHORIZED (err u102))
(define-constant ERR_INVALID_INPUT (err u103))
(define-constant ERR_BLOCKED (err u104))
(define-constant ERR_DEACTIVATED (err u105))
(define-constant ERR_RATE_LIMITED (err u106))
(define-constant ERR_BATCH_FULL (err u107))
(define-constant ERR_BATCH_EXPIRED (err u108))

;; STATUS CONSTANTS - Platform State Management

;; User Account Status Definitions
(define-constant STATUS_DEACTIVATED u0)
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_SUSPENDED u2)

;; Relationship Status Definitions
(define-constant FRIENDSHIP_PENDING u0)
(define-constant FRIENDSHIP_ACTIVE u1)
(define-constant FRIENDSHIP_BLOCKED u2)

;; PLATFORM LIMITS - Spam Protection & Resource Management

;; Daily Action Limits for Platform Stability
(define-constant MAX_ACTIONS_PER_DAY u100)
(define-constant MAX_FRIEND_REQUESTS_PER_DAY u20)
(define-constant MAX_STATUS_UPDATES_PER_DAY u24)
(define-constant RATE_LIMIT_RESET_PERIOD u86400) ;; 24 hours in seconds

;; Batch Processing Configuration
(define-constant MIN_BATCH_SIZE u10)
(define-constant MAX_BATCH_SIZE u100)
(define-constant BATCH_EXPIRY_PERIOD u3600) ;; 1 hour in seconds

;; DATA STORAGE MAPS - Core Platform State

;; Primary User Registry - Core Identity Management
(define-map Users
  principal
  {
    name: (string-ascii 64),
    status: uint,
    timestamp: uint,
    metadata: (optional (string-utf8 256)),
    deactivation-time: (optional uint),
    encryption-key: (optional (buff 32)),
    profile-image: (optional (string-utf8 256)),
  }
)

;; Privacy Control Center - Granular Visibility Settings
(define-map UserPrivacy
  principal
  {
    friend-list-visible: bool,
    status-visible: bool,
    metadata-visible: bool,
    last-seen-visible: bool,
    profile-image-visible: bool,
    encryption-enabled: bool,
    last-updated: uint,
  }
)

;; Rate Limiting Engine - Anti-Spam Protection
(define-map RateLimits
  principal
  {
    daily-actions: uint,
    friend-requests: uint,
    status-updates: uint,
    last-reset: uint,
  }
)

;; Batch Processing Optimizer - Performance Enhancement
(define-map UserBatches
  principal
  {
    message-counter: uint,
    last-batch-timestamp: uint,
    batch-size: uint,
    current-batch-items: uint,
    total-batches: uint,
  }
)

;; Activity Analytics - User Engagement Tracking
(define-map UserActivity
  principal
  {
    last-seen: uint,
    login-count: uint,
    total-actions: uint,
    last-action: uint,
  }
)

;; Social Graph Management - Friendship Relations
(define-map Friendships
  {
    user1: principal,
    user2: principal,
  }
  { status: uint }
)

;; Safety Infrastructure - User Blocking System
(define-map BlockedUsers
  {
    blocker: principal,
    blocked: principal,
  }
  { timestamp: uint }
)

;; PRIVATE UTILITY FUNCTIONS - Internal Logic Components

;; Rate Limit Validator - Automatic Reset & Validation
(define-private (check-rate-limit
    (user principal)
    (action-type uint)
  )
  (let (
      (rate-data (default-to {
        daily-actions: u0,
        friend-requests: u0,
        status-updates: u0,
        last-reset: stacks-block-height,
      }
        (map-get? RateLimits user)
      ))
      (current-time stacks-block-height)
      (should-reset (> (- current-time (get last-reset rate-data)) RATE_LIMIT_RESET_PERIOD))
    )
    (if should-reset
      (begin
        (map-set RateLimits user {
          daily-actions: u1,
          friend-requests: (if (is-eq action-type u1)
            u1
            u0
          ),
          status-updates: (if (is-eq action-type u2)
            u1
            u0
          ),
          last-reset: current-time,
        })
        true
      )
      (and
        (< (get daily-actions rate-data) MAX_ACTIONS_PER_DAY)
        (or
          (not (is-eq action-type u1))
          (< (get friend-requests rate-data) MAX_FRIEND_REQUESTS_PER_DAY)
        )
        (or
          (not (is-eq action-type u2))
          (< (get status-updates rate-data) MAX_STATUS_UPDATES_PER_DAY)
        )
      )
    )
  )
)
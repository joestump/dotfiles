---
name: go-patterns
description: Write idiomatic Go following Google/Uber style guides. Use for Go code generation, reviews, or refactoring. Emphasizes error handling, testing, concurrency patterns.
license: MIT
metadata:
  author: joe
  version: "1.0"
  stack: go
---

# Go Best Practices and Patterns

Expert Go developer following Google and Uber style guides with emphasis on production readiness.

## When to Use

- Writing new Go code
- Reviewing Go code
- Refactoring Go services
- Debugging Go issues
- User mentions "Go", "golang", or asks about Go patterns

## Core Principles

1. **Error handling is not optional** - every error must be handled or explicitly ignored
2. **Table-driven tests** - use subtests with t.Run()
3. **Context is king** - always pass context.Context as first parameter
4. **Interfaces are small** - prefer single-method interfaces
5. **Concurrency via goroutines + channels** - avoid shared state

## Code Structure

    project/
    ├── cmd/
    │   └── server/
    │       └── main.go
    ├── internal/
    │   ├── service/
    │   ├── repository/
    │   └── handler/
    ├── pkg/
    │   └── api/
    ├── go.mod
    ├── go.sum
    └── README.md

## Error Handling Pattern

    func DoSomething(ctx context.Context, id string) (*Result, error) {
        result, err := repository.Get(ctx, id)
        if err != nil {
            return nil, fmt.Errorf("failed to get result: %w", err)
        }
        
        if err := validate(result); err != nil {
            return nil, fmt.Errorf("validation failed: %w", err)
        }
        
        return result, nil
    }

**Always:**
- Return errors as last return value
- Wrap errors with context using %w
- Check errors immediately after call
- Don't use panic() in library code

## Testing Pattern

    func TestUserService_CreateUser(t *testing.T) {
        tests := []struct {
            name    string
            input   CreateUserInput
            want    *User
            wantErr bool
        }{
            {
                name: "valid user",
                input: CreateUserInput{Email: "test@example.com"},
                want: &User{Email: "test@example.com"},
                wantErr: false,
            },
            {
                name: "invalid email",
                input: CreateUserInput{Email: "invalid"},
                want: nil,
                wantErr: true,
            },
        }
        
        for _, tt := range tests {
            t.Run(tt.name, func(t *testing.T) {
                got, err := service.CreateUser(context.Background(), tt.input)
                if (err != nil) != tt.wantErr {
                    t.Errorf("CreateUser() error = %v, wantErr %v", err, tt.wantErr)
                    return
                }
                if !reflect.DeepEqual(got, tt.want) {
                    t.Errorf("CreateUser() = %v, want %v", got, tt.want)
                }
            })
        }
    }

## HTTP Handler Pattern

    func (h *Handler) CreateUser(w http.ResponseWriter, r *http.Request) {
        ctx := r.Context()
        
        var req CreateUserRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            http.Error(w, "invalid request", http.StatusBadRequest)
            return
        }
        
        user, err := h.service.CreateUser(ctx, req)
        if err != nil {
            slog.ErrorContext(ctx, "failed to create user", "error", err)
            http.Error(w, "internal error", http.StatusInternalServerError)
            return
        }
        
        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(http.StatusCreated)
        json.NewEncoder(w).Encode(user)
    }

## Concurrency Pattern

    func ProcessBatch(ctx context.Context, items []Item) error {
        g, ctx := errgroup.WithContext(ctx)
        
        for _, item := range items {
            item := item // capture loop variable
            g.Go(func() error {
                return processItem(ctx, item)
            })
        }
        
        return g.Wait()
    }

## Dependency Injection

    type Service struct {
        repo Repository
        cache Cache
        logger *slog.Logger
    }
    
    func NewService(repo Repository, cache Cache, logger *slog.Logger) *Service {
        return &Service{
            repo: repo,
            cache: cache,
            logger: logger,
        }
    }

## Common Mistakes to Avoid

- ❌ Ignoring errors: `_ = someFunc()`
- ❌ Using panic() for expected errors
- ❌ Not passing context
- ❌ Goroutine leaks (not using context cancellation)
- ❌ Using time.After() in loops (memory leak)
- ❌ Not closing http response bodies
- ❌ Forgetting to call sync.WaitGroup.Done()

## Always Include

- Comprehensive test coverage (>80%)
- godoc comments on exported functions
- Context for cancellation
- Structured logging with slog
- Proper error wrapping
- Race detector in CI: `go test -race`

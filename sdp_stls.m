% SDP relaxation for structured total least squares (STLS)
%
% Let n,m,k integers (k<=m)
% Let P: R^n -> R^{k x m} be an affine map
% Let u1 be a vector in R^n
% Consider the optimization problem
%
% min_u     |u - u1|^2
% s.t.      P(u) is rank deficient
%
% Input:
% PP - matrix of size (n+1)k x m describing the affine map P
% u1 - a vector of length n
% solver - SDP solver (default 'sdpt3')
%
% Output:
% opt - optimal value of SDP relaxation
% u - the minimizer of the problem
% U - the matrix P(u)
% z - a vector in the left kernel of P(u)
% X - the PSD matrix (relaxation is exact if rank(X)=1)

function [opt,u,U,z,X] = sdp_stls(PP,u1,solver,quiet)

if nargin < 3; solver = 'sdpt3'; end
if nargin < 4; quiet = true; end

n = length(u1);
m = size(PP,2);
k = size(PP,1)/(n+1);

% fprintf('PSD matrix size: %d\n',(n+1)*k)

u1 = reshape(u1,[1,n]);
G0 = [eye(n) -u1.'; -u1 norm(u1)^2];
E0 = sparse(n+1,n+1,1);

Ik = eye(k);
G = kron(G0,Ik);
E = kron(E0,Ik);

[opt, X, x, e] = primal_cvx(n,k,m,PP,G,E,solver,quiet);
if e==inf 
    warning('sdp failed');
elseif e>1e-4
    warning('solution is not rank one');
end

W = reshape(x,k,n+1);
z = W(:,end);
u = (sign(W(1,:)).*sqrt(sum(W.^2)))';
u = sign(u(end))*u(1:n)';
U = applyAffineMap(PP,u);

% dual sdp
function [opt, X, x, e] = dual_cvx(n,k,m,PP,G,E,solver,quiet)
N = (n+1)*k;
PC = cell(m,1);

if quiet
cvx_begin sdp quiet
else
cvx_begin sdp
end
    cvx_solver(solver)
    variable t(1,1);
    variable Cvec(N,m)
    dual variable X
    for i=1:m
        Ci = Cvec(:,i);
        pi = PP(:,i);
        PC{i} = pi*Ci';
    end
    sPC = sum(cat(3,PC{:}),3);
    sPC = blksym(n+1,k,sPC);
    maximize(t);
    Q = G - t*E + sPC;
    X: Q >= 0;
cvx_end

opt = cvx_optval;
[x,e] = recoverSol(X);

% primal sdp
function [opt, X, x, e] = primal_cvx(n,k,m,PP,G,E,solver,quiet)
N = (n+1)*k;

e = speye(N);
PC = zeros(N,N,m*N);
for i=1:m
    for j=1:N
        PC(:,:,(i-1)*N+j) = PP(:,i)*e(j,:);
    end
end
PC = blksym(n+1,k,PC);
A = zeros(m*N,N*(N+1)/2);
for l=1:m*N
    A(l,:) = smat2vec(PC(:,:,l));
end
A = sparse(A);

if quiet
cvx_begin sdp quiet
else
cvx_begin sdp
end
    cvx_solver(solver)
    variable X(N,N) symmetric
    dual variable Q
    y = smat2vec(X);
    minimize(smat2vec(G)'*y);
    smat2vec(E)'*y == 1;
    A*y == 0;
    Q: X >= 0;
cvx_end

opt = cvx_optval;
[x,e] = recoverSol(X);

% recover minimizer from moment matrix
function [x,e] = recoverSol(X)
N = size(X,1);
if any(isnan(X))
    x = nan(N,1);
    e = inf;
else
    [V,E] = eig(full(X)); 
    e=diag(E);
    x = sqrt(e(N))*V(:,N);
    e = e(N-1);
end

% vector to symmetric matrix
function M = vec2smat(v)

N = length(v);
n = (-1+sqrt(1+8*N))/2;

M = repmat(0*v(1:n),[1,n]);
I = triu(true(n,n),0);
I2 = triu(true(n,n),1);
M(I) = v/2;
M(I2) = M(I2)*sqrt(2);
M = M + M.';

% symmetric matrix to vector
function v = smat2vec(M)

n = size(M,1);
I = triu(true(n,n),0);
I2 = triu(true(n,n),1);
M(I2) = M(I2)*sqrt(2);
v = M(I);

% Block symmetrization of a matrix
% Input: mk x mk matrix A
% Output: symmetric matrix S such that 
%         each k x k block is also symmetric (there are m^2 blocks)
function S = blksym(m,k,A)

S = mysym(A);
if isempty(A); return; end

for i=1:m
    for j=1:m
        I = k*(i-1) + (1:k);
        J = k*(j-1) + (1:k);
        S(I,J,:) = mysym(S(I,J,:));
    end
end

% symmetrize matrix
function As = mysym(A)
At = permute(A,[[2,1],3:ndims(A)]);
As = .5*(A+At);
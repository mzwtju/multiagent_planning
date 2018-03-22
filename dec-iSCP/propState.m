function [p,v] = propState(po, a, h)

% Kinematic model A,b matrices
A = [1 0 0 h 0 0;
     0 1 0 0 h 0;
     0 0 1 0 0 h;
     0 0 0 1 0 0;
     0 0 0 0 1 0;
     0 0 0 0 0 1];

b = [h^2/2*eye(3);
     h*eye(3)];

K = length(a)/3;

vo = [0 0 0];

prev_row = zeros(6,3*K); % For the first iteration of constructing matrix Ain
A_p = [];
A_v = [];

% Build matrix to convert acceleration to position
for k = 1:(K-1)
    add_b = [zeros(size(b,1),size(b,2)*(k-1)) b zeros(size(b,1),size(b,2)*(K-k))];
    new_row = A*prev_row + add_b;   
    A_p = [A_p; new_row(1:3,:)];
    A_v = [A_v; new_row(4:6,:)];
    prev_row = new_row; 
end

new_p = A_p*a;
new_v = A_v*a;

p = [po'; new_p + repmat(po',K-1,1)];
v = [vo'; new_v];
end
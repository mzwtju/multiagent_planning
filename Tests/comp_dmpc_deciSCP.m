clc
clear all
close all
warning('off','all')

% Time settings and variables
T = 15; % Trajectory final time
h = 0.2; % time step duration
tk = 0:h:T;
K = T/h + 1; % number of time steps
Ts = 0.01; % period for interpolation @ 100Hz
t = 0:Ts:T; % interpolated time vector
k_hor = 15;
success = 1;
N_vector = 2:4:30; % number of vehicles
trials = 50;
fail4 = 0;

% Variables for ellipsoid constraint
order = 2; % choose between 2 or 4 for the order of the super ellipsoid
rmin = 0.5; % X-Y protection radius for collisions
c = 1.5; % make this one for spherical constraint
E = diag([1,1,c]);
E1 = E^(-1);
E2 = E^(-order);

% Workspace boundaries
pmin = [-2.5,-2.5,0.2];
pmax = [2.5,2.5,2.2];

% Minimum distance between vehicles in m
rmin_init = 0.75;

% Maximum acceleration in m/s^2
alim = 0.5;

% Some Precomputations dec-iSCP
% Kinematic model A,b matrices
A = [1 0 0 h 0 0;
     0 1 0 0 h 0;
     0 0 1 0 0 h;
     0 0 0 1 0 0;
     0 0 0 0 1 0;
     0 0 0 0 0 1];

b = [h^2/2*eye(3);
     h*eye(3)];
 
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

% Some pre computations DMPC
A = getPosMat(h,k_hor);
Aux = [1 0 0 h 0 0;
     0 1 0 0 h 0;
     0 0 1 0 0 h;
     0 0 0 1 0 0;
     0 0 0 0 1 0;
     0 0 0 0 0 1];
A_initp = [];
A_init = eye(6);
tol = 2;

Delta = getDeltaMat(k_hor); 

for k = 1:k_hor
    A_init = Aux*A_init;
    A_initp = [A_initp; A_init(1:3,:)];  
end

% Start Test

for q = 1:length(N_vector)
    N = N_vector(q);
    for r = 1:trials
        fprintf("Doing trial #%i with %i vehicles\n",r,N)
        % Initial positions
        [po,pf] = randomTest(N,pmin,pmax,rmin_init);

        % Empty list of obstacles
        l = [];
        
        % DEC-ISCP
        t_start = tic; 
        for i = 1:N 
            poi = po(:,:,i);
            pfi = pf(:,:,i);
            [pi, vi, ai,success] = singleiSCP(poi,pfi,h,K,pmin,pmax,rmin,alim,l,A_p,A_v,E1,E2,order);
            if ~success
                break;
            end
            l = cat(3,l,pi);
            pk(:,:,i) = pi;
            vk(:,:,i) = vi;
            ak(:,:,i) = ai;

            % Interpolate solution with a 100Hz sampling
            p(:,:,i) = spline(tk,pi,t);
            v(:,:,i) = spline(tk,vi,t);
            a(:,:,i) = spline(tk,ai,t);
        end
        if success
            t_dec(q,r) = toc(t_start);
            totdist_dec(q,r) = sum(sum(sqrt(diff(p(1,:,:)).^2+diff(p(2,:,:)).^2+diff(p(3,:,:)).^2)));
        
        else
            t_dec(q,r) = nan;
            totdist_dec(q,r) = nan;
        end
        success_dec(q,r) = success;
        
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%      
        
        %SoftDMPC with 
        
        % Variables for ellipsoid constraint
        order = 2; % choose between 2 or 4 for the order of the super ellipsoid
        rmin = 0.5; % X-Y protection radius for collisions
        c = 1.5; % make this one for spherical constraint
        E = diag([1,1,c]);
        E1 = E^(-1);
        E2 = E^(-order);
        term4 = -5*10^4;
        
        l = [];
        feasible4(q,r) = 0; %check if QP was feasible
        error_tol = 0.05; % 5cm destination tolerance
        violation4(q,r) = 0; % checks if violations occured at end of algorithm

        % Penalty matrices when there're predicted collisions
        Q = 1000;
        S = 100;
        failed_goal4(q,r) = 0;
        outbound4(q,r) = 0;
        t_start = tic;
        
        for k = 1:K
            for n = 1:N
                if k==1
                    poi = po(:,:,n);
                    pfi = pf(:,:,n);
                    [pi,vi,ai] = initDMPC(poi,pfi,h,k_hor,K);
                    feasible4(q,r) = 1;
                else
                    pok = pk(:,k-1,n);
                    vok = vk(:,k-1,n);
                    aok = ak(:,k-1,n);
                    [pi,vi,ai,feasible4(q,r),outbound4(q,r)] = solveSoftDMPCrepair(pok',pf(:,:,n),vok',aok',n,h,l,k_hor,rmin,pmin,pmax,alim,A,A_initp,Delta,Q,S,E1,E2,order,term4); 
                end
                if ~feasible4(q,r)
                    break;
                end
                new_l(:,:,n) = pi;
                pk(:,k,n) = pi(:,1);
                vk(:,k,n) = vi(:,1);
                ak(:,k,n) = ai(:,1);
            end
            if ~feasible4(q,r)
                save(['Fail4_' num2str(fail4)]);
                fail4 = fail4 + 1;
                break;
            end
            l = new_l;
        end
        if feasible4(q,r)
            pass = ReachedGoal(pk,pf,K,error_tol,N);
            if  ~pass
                failed_goal4(q,r) = failed_goal4(q,r) + 1;
            end
        end

        if feasible4(q,r) && ~failed_goal4(q,r)       
            for i = 1:N
                p(:,:,i) = spline(tk,pk(:,:,i),t);
                v(:,:,i) = spline(tk,vk(:,:,i),t);
                a(:,:,i) = spline(tk,ak(:,:,i),t); 
            end
            % Check if collision constraints were not violated
            for i = 1:N
                for j = 1:N
                    if(i~=j)
                        differ = E1*(p(:,:,i) - p(:,:,j));
                        dist = (sum(differ.^order,1)).^(1/order);
                        if min(dist) < (rmin - 0.05)
                            [value,index] = min(dist);
                            violation4(q,r) = 1;
                        end
                    end
                end
            end
            t_dmpc(q,r) = toc(t_start);
            totdist_dmpc(q,r) = sum(sum(sqrt(diff(p(1,:,:)).^2+diff(p(2,:,:)).^2+diff(p(3,:,:)).^2)));
            
            for i = 1:N
                diff_goal = p(:,:,i) - repmat(pf(:,:,i),length(t),1)';
                dist_goal = sqrt(sum(diff_goal.^2,1));
                hola = find(dist_goal >= 0.05,1,'last');
                if isempty(hola)
                    time_index(i) = 0;
                else
                    time_index(i) = hola + 1;
                end
            end
            traj_time(q,r) = max(time_index)*Ts;
        else
            t_dmpc(q,r) = nan;
            totdist_dmpc(q,r) = nan;
            traj_time(q,r) = nan;
        end
        success_dmpc(q,r) = feasible4(q,r) && ~failed_goal4(q,r) && ~violation4(q,r);
    end
end
fprintf("Finished! \n")
save('comp_deciSCP_vs_DMPC3')
%% Post-Processing

% Probability of success plots
prob_dec = sum(success_dec,2)/trials;
prob_dmpc = sum(success_dmpc,2)/trials;
figure(1)
plot(N_vector,prob_dec','Linewidth',2);
grid on;
hold on;
ylim([0,1.05])
plot(N_vector,prob_dmpc,'Linewidth',2);
xlabel('Number of Vehicles');
ylabel('Success Probability');
legend('dec-iSCP','DMPC');

% Computation time
tmean_dec = nanmean(t_dec,2);
tstd_dec = nanstd(t_dec,1,2);
tmean_dmpc = nanmean(t_dmpc,2);
tstd_dmpc = nanstd(t_dmpc,1,2);
figure(2)
plot(N_vector, tmean_dec,'LineWidth',2);
% errorbar(N_vector,tmean_dec,tstd_dec,'Linewidth',2);
grid on;
hold on;
xlim([4 30]);
plot(N_vector, tmean_dmpc,'LineWidth',2);
% errorbar(N_vector,tmean_dmpc,tstd_dmpc,'Linewidth',2);
xlabel('Number of Vehicles');
ylabel('Average Computation Time [s]');
legend('dec-iSCP','DMPC');

% Percentage increase/decrease on travelled dist of dmpc wrt dec
% Positive number means that dmpc path was longer
diff_dist = (totdist_dmpc-totdist_dec)./totdist_dec;
avg_diff = nanmean(diff_dist,2);
std_diff = nanstd(diff_dist,1,2);
figure(3)
plot(N_vector, 100*avg_diff,'LineWidth', 2);
% errorbar(N_vector,100*avg_diff,100*std_diff,'Linewidth',2);
grid on;
xlabel('Number of Vehicles');
ylabel('Average % increase/decrease');
% title('Percentual increase/decrease on total travelled distance of DMPC wrt dec-iSCP');
legend('DMPC w.r.t. dec-iSCP')
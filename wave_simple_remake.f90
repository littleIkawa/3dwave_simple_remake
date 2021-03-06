program main
    use,intrinsic :: iso_fortran_env
    use utils
    implicit none

    REAL(real64),PARAMETER :: PI = acos(-1.0d0)
    INTEGER,PARAMETER :: NUM_TIME_STEP = 20
    REAL(real64),PARAMETER :: ALMOST0 = 1.0d-8
    REAL(real64),PARAMETER :: WAVE_VELOCITY = 1.0d0
    REAL(real64),PARAMETER :: WAVE_LENGTH = 1.0d0
    ! 直径2の球に内接する正二十面体の一辺の長さ/meshパラメータの値を計算している.
    REAL(real64),PARAMETER :: TIME_INCREMENT = 2.0d0/sqrt((5.0d0+sqrt(5.0d0))/2.0d0)/6.0d0
    ! REAL(real64) :: wvwv = WAVE_VELOCITY**2
    INTEGER :: NUM_POINT, NUM_ELEMENT
    REAL(real64) :: s_layer, d_layer
    REAL(real64) :: tc

    REAL(real64),ALLOCATABLE :: points(:,:)  ! 点の3軸座標の配列
    INTEGER,ALLOCATABLE :: elements(:,:)  ! 三角形の点番号3つの配列
    INTEGER :: point_num, el_num, el_num2, axis_num, time_step, time_step2  ! 繰り返し用変数
    REAL(real64) :: element(3,3)  ! 三角形一つの座標を保持する
    REAL(real64) :: center(3)  ! 三角形の重心
    REAL(real64) :: xce(6), yce(3), zce
    REAL(real64),ALLOCATABLE :: yt(:,:,:), yn(:,:,:), yh(:,:)  ! 要素から作る正規直交基底
    REAL(real64),ALLOCATABLE :: s_matrix(:,:,:), d_matrix(:,:,:), c_matrix(:,:)
    REAL(real64),ALLOCATABLE :: elem_u(:,:)
    REAL(real64),ALLOCATABLE :: b_vector(:,:)

    REAL(real64) :: direction(3) = [0.0d0, 0.0d0, 1.0d0]  ! 波の進行方向（単位ベクトル）
    REAL(real64) :: temp, temp2, time
    INTEGER,ALLOCATABLE :: boundary_condition(:)  ! 境界条件を要素ごとに設定する配列
    INTEGER,ALLOCATABLE :: ipiv(:)  ! lapackで解く際にピボットを保存する配列
    INTEGER :: dgesv_info
    REAL(real64) :: exact_v  ! 厳密解

    ! メッシュのパラメータ読み込み
    open(22, file="mesh/meshparam.h", status="old")
    read(22,*)NUM_POINT, NUM_ELEMENT
    close(22)

    ALLOCATE(boundary_condition(NUM_ELEMENT))
    ALLOCATE(ipiv(NUM_ELEMENT))

    ALLOCATE(points(3, NUM_POINT))
    ALLOCATE(elements(3, NUM_ELEMENT))
    ALLOCATE(yt(3, 3, NUM_ELEMENT), source=0.0d0)
    ALLOCATE(yn(3, 3, NUM_ELEMENT), source=0.0d0)
    ALLOCATE(yh(3, NUM_ELEMENT), source=0.0d0)
    ! 行列は0で埋めておく
    ALLOCATE(elem_u(NUM_ELEMENT, NUM_TIME_STEP), source=0.0d0)
    ALLOCATE(b_vector(NUM_ELEMENT, NUM_TIME_STEP), source=0.0d0)
    ALLOCATE(s_matrix(NUM_ELEMENT, NUM_ELEMENT, 0:NUM_TIME_STEP), source=0.0d0)
    ALLOCATE(d_matrix(NUM_ELEMENT, NUM_ELEMENT, 0:NUM_TIME_STEP), source=0.0d0)
    ALLOCATE(c_matrix(NUM_ELEMENT, NUM_ELEMENT), source=0.0d0)

    ! read mesh data
    open(20, file='mesh/pmesh', status='old')
    open(21, file='mesh/nmesh', status='old')
    do point_num = 1, NUM_POINT
        read(20,*) points(1, point_num), points(2, point_num), points(3, point_num)
    enddo
    do el_num = 1, NUM_ELEMENT
        read(21,*) elements(1, el_num), elements(3, el_num), elements(2, el_num)
        boundary_condition(el_num) = -1  ! 1: Dirichlet, -1: Neumann
    end do
    close(20)
    close(21)

    ! write mesh by gnuplot
    call space_plot(NUM_ELEMENT, points, elements)

    ! 名前付き構文と継続行構文を用いている
    make_boundary_condition :&
    do el_num = 1, NUM_ELEMENT
        ! elem_num番の要素を取得
        element(:,:) = points(:,elements(:, el_num))
        call calc_tnh(element(:,:), yt(:,:,el_num), yn(:,:,el_num), yh(:,el_num))

        ! 三角形の重心を計算（色々試している）
        ! center(:) = sum(points(:,elements(:,el_num)), dim=2)/3.0d0
        center(:) = sum(element(:,:), dim=2)/3.0d0
        ! do axis_num=1, 3
        !     center(axis_num) = 0.0d0
        !     center(axis_num) = center(axis_num) + points(axis_num,elements(1,el_num))
        !     center(axis_num) = center(axis_num) + points(axis_num,elements(2,el_num))
        !     center(axis_num) = center(axis_num) + points(axis_num,elements(3,el_num))
        !     center(axis_num) = center(axis_num)/3.0d0
        ! enddo

        ! tempは波がcenterにとどくまでの時間. それより早い時間ではelem_uは0.
        temp = dot_product(direction(:), center(:))/WAVE_VELOCITY
        if (boundary_condition(el_num) == 1) then  ! Dirichlet
            ! do time_step = 1, NUM_TIME_STEP
            !     time = TIME_INCREMENT*time_step
            !     elem_u(el_num, time_step)=0.0d0
            !     if (time > temp) then  ! 波が到達しているなら
            !         elem_u(el_num, time_step) = 1.0d0 - cos(2.0d0*PI*(time - temp)/WAVE_LENGTH)
            !     endif
            ! enddo
        else if (boundary_condition(el_num) == -1) then  ! Neumann
            temp2 = dot_product(direction(:), yh(:,el_num))
            temp2 = 2.0d0*PI*temp2/WAVE_VELOCITY/WAVE_LENGTH
            do time_step = 1, NUM_TIME_STEP
                time = TIME_INCREMENT*time_step
                ! elem_u(el_num, time_step)=0.0d0
                if (time > temp) then
                    elem_u(el_num, time_step) = -temp2*sin(2.0d0*PI*(time - temp)/WAVE_LENGTH)
                endif
            enddo
        else
            print *,'wrong b.c.'
            stop
        endif
    end do&
    make_boundary_condition

    !!!! main !!!!
    time_loop :&
    do time_step = 1, NUM_TIME_STEP
        print *,'time_step=',time_step
        time = TIME_INCREMENT*time_step
        tc = time*WAVE_VELOCITY

        element_loop2 :&
        do el_num2 = 1, NUM_ELEMENT
            element(:,:) = points(:,elements(:, el_num2))

            element_loop :&
            do el_num = 1, NUM_ELEMENT
                s_layer = 0.0d0
                d_layer = 0.0d0
                center(:) = sum(points(:,elements(:,el_num)), dim=2)/3.0d0
                CALL calc_xyz(center(:), element(:,:), yt(:,:,el_num2),&
                    yn(:,:,el_num2), yh(:,el_num2), xce(:), yce(:), zce, ALMOST0)

                ! 行列の係数を計算
                if ( tc > abs(zce) ) then  ! t*c > |z|
                    do axis_num = 1, 3
                        if (abs(yce(axis_num)) > ALMOST0) then  ! |y| > 0
                            call calc_s_d_layer(tc, xce(2*axis_num-1), yce(axis_num), zce, s_layer, d_layer)
                        endif
                    enddo
                endif
                ! store
                if (boundary_condition(el_num2) == -1) then
                    s_matrix(el_num, el_num2, time_step) = 0.25*s_layer/PI
                    d_matrix(el_num, el_num2, time_step) = 0.25*d_layer/PI
                else if (boundary_condition(el_num2) == 1) then
                    s_matrix(el_num, el_num2, time_step) = -0.25*d_layer/PI
                    d_matrix(el_num, el_num2, time_step) = -0.25*s_layer/PI
                else
                    print *,'wrong b.c.'
                    stop
                endif
            end do element_loop
        end do element_loop2

        do time_step2=1,time_step
            do el_num2=1,NUM_ELEMENT
                do el_num=1,NUM_ELEMENT
                    b_vector(el_num,time_step) = b_vector(el_num,time_step)+&
                                               (s_matrix(el_num,el_num2,time_step-time_step2+1)&
                                                    -s_matrix(el_num,el_num2,time_step-time_step2))&
                                                        *elem_u(el_num2,time_step2)
                enddo
            enddo
            print *,'+S(',time_step-time_step2+1,'-',time_step-time_step2,')*q(',time_step2,')'
        enddo

        if (time_step.ge.2) then
            do time_step2=2,time_step
                do el_num2=1,NUM_ELEMENT
                    do el_num=1,NUM_ELEMENT
                        b_vector(el_num,time_step) = b_vector(el_num,time_step)&
                            -(d_matrix(el_num,el_num2,time_step-time_step2+2)&
                                -d_matrix(el_num,el_num2,time_step-time_step2+1))&
                                    *b_vector(el_num2,time_step2-1)
                    enddo
                enddo
                print *,'-D(',time_step-time_step2+2,'-',time_step-time_step2+1,')*u(',time_step2-1,')'
            enddo
        endif

        do el_num = 1, NUM_ELEMENT
            center(:) = sum(points(:,elements(:,el_num)), dim=2)/3.0d0
            temp = dot_product(direction(:), center(:))/WAVE_VELOCITY
            if (time > temp) then
                b_vector(el_num, time_step) =&
                            b_vector(el_num, time_step) + 1.0d0 - cos(2.0d0*PI*(time-temp)/WAVE_LENGTH)
            endif
        enddo

        ! solver
        ! do el_num2 = 1, NUM_ELEMENT
        !     do el_num = 1, NUM_ELEMENT
        !         c_matrix(el_num ,el_num2) = d_matrix(el_num, el_num2, 1)
        !     enddo
        ! enddo
        c_matrix(:,:) = d_matrix(:, :, 1)
        do el_num = 1, NUM_ELEMENT
            center(:) = sum(points(:,elements(:,el_num)), dim=2)/3.0d0
            ! そのときの解を出力している
            ! write(20+time_step,*)center(3), b_vector(el_num,1), el_num
        enddo
        if (time_step == 1) then
            print *,'c_mat_ii=',c_matrix(1,1)
        endif
        call dgesv(NUM_ELEMENT, 1, c_matrix(:,:), NUM_ELEMENT,&
                        ipiv, b_vector(1, time_step), NUM_ELEMENT, dgesv_info)
        if (dgesv_info /= 0) print *,'INFO=',dgesv_info

        ! 厳密解を作る
        do el_num = 1, NUM_ELEMENT
            exact_v=0.
            center(:) = sum(points(:,elements(:,el_num)), dim=2)/3.0d0
            temp = dot_product(direction, center)/WAVE_VELOCITY
            if (boundary_condition(el_num) == 1) then ! Dirichlet
                ! temp2 = dot_product(direction, yh(:,el_num))
                ! temp2 = 2.0d0*PI*temp2/WAVE_VELOCITY/WAVE_LENGTH
                ! if (time > temp) then
                !     exact_v = -temp2*sin(2.0d0*PI*(time-temp)/WAVE_LENGTH)
                ! endif
            else if (boundary_condition(el_num) == -1) then               ! Neumann
                if (time > temp) then
                    exact_v = 1.0d0-cos(2.0d0*PI*(time-temp)/WAVE_LENGTH)
                endif
            else
                print *,'wrong b.c.'
                stop
            endif
            write(50+time_step,*)center(3), b_vector(el_num,time_step), exact_v, el_num
            if (el_num == 1) write(40,*)time, b_vector(1,time_step), exact_v, center(3)
            if (el_num == 37) write(41,*)time, b_vector(37,time_step), exact_v, center(3)
        enddo
    end do time_loop

end program main